# R.E.P.O. Backup: тёмное окно с круглой кнопкой. Пока кнопка включена, сейвы копируются каждую минуту.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

# Скрываем консоль. Этот же вызов «съедает» флаг скрытого запуска, иначе окно программы тоже было бы невидимым.
Add-Type -Name Win -Namespace Native -MemberDefinition '
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);'
[void][Native.Win]::ShowWindow([Native.Win]::GetConsoleWindow(), 0)

# Только один экземпляр: если программа уже открыта, показываем её окно и выходим
$script:mutex = New-Object Threading.Mutex($false, "Local\TaleTales.REPOBackup")
try   { $first = $script:mutex.WaitOne(0) }
catch [Threading.AbandonedMutexException] { $first = $true }   # прошлый экземпляр завершился аварийно
if (-not $first) {
    $h = [Native.Win]::FindWindow([NullString]::Value, "R.E.P.O. Backup")   # $null PowerShell передал бы как ""
    if ($h -ne [IntPtr]::Zero) {
        if ([Native.Win]::IsIconic($h)) { [void][Native.Win]::ShowWindow($h, 9) }   # 9 = SW_RESTORE
        [void][Native.Win]::SetForegroundWindow($h)
    }
    exit
}
# свой ID приложения: отдельная кнопка на панели задач со своей иконкой, а не значок PowerShell
[void][Native.Win]::SetCurrentProcessExplicitAppUserModelID("TaleTales.REPOBackup")

# Перехват сворачивания (кнопка на панели задач, Win+↓): вместо мгновенного сворачивания запускаем свою анимацию
$wpf = [Windows.Window].Assembly.Location, [Windows.Media.Visual].Assembly.Location,
       [Windows.Threading.Dispatcher].Assembly.Location, [System.Xaml.XamlReader].Assembly.Location
Add-Type -ReferencedAssemblies $wpf -TypeDefinition @'
using System; using System.Windows; using System.Windows.Interop;
public static class MinHook {
    public static Action OnMinimize;
    public static void Attach(Window w) {
        HwndSource.FromHwnd(new WindowInteropHelper(w).Handle).AddHook(Hook);
    }
    static IntPtr Hook(IntPtr h, int msg, IntPtr wp, IntPtr lp, ref bool handled) {
        if (msg == 0x0112 && (wp.ToInt64() & 0xFFF0) == 0xF020 && OnMinimize != null) { handled = true; OnMinimize(); }
        return IntPtr.Zero;
    }
}
'@

# Карточка в списке: либо игра (папка с копиями), либо отдельная копия
Add-Type -TypeDefinition 'public class BackupItem { public string Kind {get;set;} public string Title {get;set;} public string Sub {get;set;} public string Save {get;set;} public string Path {get;set;} public string Icon {get;set;} public string IconColor {get;set;} }'

$src  = "$env:USERPROFILE\AppData\LocalLow\semiwork\Repo\saves"
$dst  = "$PSScriptRoot\saves"
$keep = 30   # сколько последних копий хранить на каждый сейв
$AppVersion = "1.4.0"   # при выпуске новой версии менять и здесь, и тег релиза на GitHub

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="R.E.P.O. Backup" Width="420" Height="720" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI Variable Display, Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Accent" Color="#FBB26A"/>
    <FontFamily x:Key="Icons">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
    <CubicEase x:Key="Out" EasingMode="EaseOut"/>

    <Style x:Key="IconBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#878B91"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="8" Width="34" Height="34">
            <Border.Background><SolidColorBrush Color="#000E0E11"/></Border.Background>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                              TextElement.FontFamily="{StaticResource Icons}" TextElement.FontSize="12"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter Property="Foreground" Value="#D7D8DB"/>
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#24252A" Duration="0:0:0.15"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#000E0E11" Duration="0:0:0.25"/>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <Style x:Key="MainBtn" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="#0E0E11"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Height" Value="48"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="12" RenderTransformOrigin="0.5,0.5">
            <Border.RenderTransform><ScaleTransform/></Border.RenderTransform>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="Opacity" To="0.86" Duration="0:0:0.15"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.25"/>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="0.96" Duration="0:0:0.08"/>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="0.96" Duration="0:0:0.08"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.35"><DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.35"><DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction></DoubleAnimation>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <Style x:Key="GhostBtn" TargetType="Button" BasedOn="{StaticResource MainBtn}">
      <Setter Property="Foreground" Value="#D7D8DB"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" BorderBrush="#2C2D30" BorderThickness="1" CornerRadius="12" RenderTransformOrigin="0.5,0.5">
            <Border.Background><SolidColorBrush Color="#1C1D21"/></Border.Background>
            <Border.RenderTransform><ScaleTransform/></Border.RenderTransform>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#26272C" Duration="0:0:0.15"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#1C1D21" Duration="0:0:0.25"/>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="0.95" Duration="0:0:0.08"/>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="0.95" Duration="0:0:0.08"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.35"><DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                <DoubleAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.35"><DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction></DoubleAnimation>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <!-- крестик удаления на карточке: виден только при наведении на карточку -->
    <Style x:Key="DelBtn" TargetType="Button">
      <Setter Property="Opacity" Value="0"/>
      <Setter Property="Foreground" Value="#878B91"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="ToolTip" Value="Удалить"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="8" Width="32" Height="32">
            <Border.Background><SolidColorBrush Color="#00FF6B6B"/></Border.Background>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                              TextElement.FontFamily="{StaticResource Icons}" TextElement.FontSize="11"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter Property="Foreground" Value="#FF6B6B"/>
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#2EFF6B6B" Duration="0:0:0.15"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#00FF6B6B" Duration="0:0:0.25"/>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
      <Style.Triggers>
        <DataTrigger Binding="{Binding IsMouseOver, RelativeSource={RelativeSource AncestorType=ListBoxItem}}" Value="True">
          <DataTrigger.EnterActions><BeginStoryboard><Storyboard>
            <DoubleAnimation Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
          </Storyboard></BeginStoryboard></DataTrigger.EnterActions>
          <DataTrigger.ExitActions><BeginStoryboard><Storyboard>
            <DoubleAnimation Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.2"/>
          </Storyboard></BeginStoryboard></DataTrigger.ExitActions>
        </DataTrigger>
      </Style.Triggers>
    </Style>

    <!-- текстовая кнопка «Очистить старые» -->
    <Style x:Key="LinkBtn" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="7" Padding="8,3">
            <Border.Background><SolidColorBrush Color="#00FBB26A"/></Border.Background>
            <TextBlock x:Name="t" Text="{TemplateBinding Content}" Foreground="#878B91"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="t" Property="Foreground" Value="#FBB26A"/>
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#1FFBB26A" Duration="0:0:0.15"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="b" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#00FBB26A" Duration="0:0:0.25"/>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <!-- переключатель-«таблетка» для настроек -->
    <Style x:Key="Toggle" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Border x:Name="track" Width="44" Height="24" CornerRadius="12" Background="#2C2D30">
            <Ellipse x:Name="knob" Width="18" Height="18" Fill="#878B91" HorizontalAlignment="Left" Margin="3,0,0,0">
              <Ellipse.RenderTransform><TranslateTransform/></Ellipse.RenderTransform>
            </Ellipse>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="track" Property="Background" Value="#FBB26A"/>
              <Setter TargetName="knob" Property="Fill" Value="#0E0E11"/>
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="knob" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" To="20" Duration="0:0:0.2">
                  <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <DoubleAnimation Storyboard.TargetName="knob" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" To="0" Duration="0:0:0.2">
                  <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="6"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True">
            <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb">
              <Border CornerRadius="3" Background="#3A3B40"/>
            </ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          </Track>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>

    <Style TargetType="ListBoxItem">
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="c" BorderBrush="#1C1D21" BorderThickness="1.5"
                  CornerRadius="12" Padding="12,10" Margin="0,0,8,8" Cursor="Hand">
            <Border.Background><SolidColorBrush Color="#1C1D21"/></Border.Background>
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Trigger.EnterActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="c" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#24252A" Duration="0:0:0.15"/>
              </Storyboard></BeginStoryboard></Trigger.EnterActions>
              <Trigger.ExitActions><BeginStoryboard><Storyboard>
                <ColorAnimation Storyboard.TargetName="c" Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)" To="#1C1D21" Duration="0:0:0.3"/>
              </Storyboard></BeginStoryboard></Trigger.ExitActions>
            </Trigger>
            <Trigger Property="IsSelected" Value="True"><Setter TargetName="c" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="18" Background="#0E0E11" BorderBrush="#24252A" BorderThickness="1" Opacity="0" RenderTransformOrigin="0.5,0.85">
    <Border.RenderTransform>
      <TransformGroup>
        <ScaleTransform x:Name="RootScale" ScaleX="0.96" ScaleY="0.96"/>
        <TranslateTransform x:Name="RootShift" Y="24"/>
      </TransformGroup>
    </Border.RenderTransform>
    <Grid>
      <Grid Margin="24,0,24,24">
        <Grid.RowDefinitions>
          <RowDefinition Height="56"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- шапка -->
        <Grid x:Name="Header" Background="Transparent" Margin="-8,0,-12,0">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="8,0,0,0">
            <Ellipse x:Name="Dot" Width="8" Height="8" Margin="0,1,10,0"/>
            <TextBlock Text="R.E.P.O. Backup" Foreground="#D7D8DB" FontSize="15" FontWeight="SemiBold"/>
            <TextBlock x:Name="VerText" Foreground="#5A5D63" FontSize="12" Margin="8,2,0,0" VerticalAlignment="Center"
                       Cursor="Hand" ToolTip="Проверить обновления"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
            <Button x:Name="SetBtn" Style="{StaticResource IconBtn}" Content="&#xE713;" ToolTip="Настройки"/>
            <Button x:Name="MinBtn" Style="{StaticResource IconBtn}" Content="&#xE921;"/>
            <Button x:Name="CloseBtn" Style="{StaticResource IconBtn}" Content="&#xE8BB;"/>
          </StackPanel>
        </Grid>

        <!-- кнопка питания -->
        <Grid x:Name="Power" Grid.Row="1" Width="200" Height="200" Margin="0,28,0,0" Cursor="Hand"
              Background="Transparent" RenderTransformOrigin="0.5,0.5">
          <Grid.RenderTransform><ScaleTransform x:Name="PowerScale" ScaleX="0.85" ScaleY="0.85"/></Grid.RenderTransform>
          <Ellipse x:Name="Glow" Fill="{StaticResource Accent}" Opacity="0" Margin="6">
            <Ellipse.Effect><BlurEffect Radius="55"/></Ellipse.Effect>
          </Ellipse>
          <Ellipse x:Name="Ripple" Stroke="{StaticResource Accent}" StrokeThickness="2" Opacity="0" RenderTransformOrigin="0.5,0.5">
            <Ellipse.RenderTransform><ScaleTransform x:Name="RippleScale"/></Ellipse.RenderTransform>
          </Ellipse>
          <Ellipse x:Name="Ring" Fill="#141519" StrokeThickness="4"/>
          <Ellipse x:Name="Arc" Stroke="#FFEBD3" StrokeThickness="4" StrokeDashArray="16 138" StrokeDashCap="Round"
                   Opacity="0" RenderTransformOrigin="0.5,0.5">
            <Ellipse.RenderTransform><RotateTransform x:Name="ArcRot"/></Ellipse.RenderTransform>
          </Ellipse>
          <Ellipse Margin="20" Fill="#1C1D21"/>
          <TextBlock x:Name="PowerIcon" Text="&#xE7E8;" FontFamily="{StaticResource Icons}" FontSize="62"
                     HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
            <TextBlock.RenderTransform><ScaleTransform x:Name="IconScale"/></TextBlock.RenderTransform>
          </TextBlock>
        </Grid>

        <StackPanel Grid.Row="2" Margin="0,26,0,0">
          <TextBlock x:Name="StateText" Foreground="#D7D8DB" FontSize="24" FontWeight="SemiBold" HorizontalAlignment="Center">
            <TextBlock.RenderTransform><TranslateTransform x:Name="StateShift"/></TextBlock.RenderTransform>
          </TextBlock>
          <TextBlock x:Name="SubText" Foreground="#878B91" FontSize="13" HorizontalAlignment="Center" Margin="0,6,0,0"/>
        </StackPanel>

        <Grid Grid.Row="3" Margin="0,30,0,12">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="BackBtn" Style="{StaticResource IconBtn}" Content="&#xE72B;" ToolTip="Ко всем играм"
                    Margin="-10,-10,2,-10" Visibility="Collapsed"/>
            <TextBlock x:Name="SectionTitle" Text="Игры" Foreground="#D7D8DB" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,-8,0">
            <TextBlock x:Name="CountText" Foreground="#5A5D63" FontSize="13" VerticalAlignment="Center"/>
            <Button x:Name="CleanBtn" Style="{StaticResource LinkBtn}" Content="Очистить старые" Margin="6,0,0,0" Visibility="Collapsed"/>
          </StackPanel>
        </Grid>

        <Grid Grid.Row="4">
          <ListBox x:Name="List" Background="Transparent" BorderThickness="0" Margin="0,0,-8,0"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <Button x:Name="DelBtn" Grid.Column="2" Style="{StaticResource DelBtn}" Content="&#xE711;" Tag="{Binding}" VerticalAlignment="Center"/>
                  <Border Width="38" Height="38" CornerRadius="10" Background="#26272C">
                    <TextBlock Text="{Binding Icon}" FontFamily="{StaticResource Icons}" FontSize="16"
                               Foreground="{Binding IconColor}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="{Binding Title}" Foreground="#D7D8DB" FontSize="14" FontWeight="SemiBold"/>
                    <TextBlock Text="{Binding Sub}" Foreground="#878B91" FontSize="12" Margin="0,2,0,0"/>
                  </StackPanel>
                </Grid>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <StackPanel x:Name="Empty" VerticalAlignment="Center" HorizontalAlignment="Center">
            <TextBlock Text="&#xE8B7;" FontFamily="{StaticResource Icons}" FontSize="34" Foreground="#3A3B40" HorizontalAlignment="Center"/>
            <TextBlock Text="Копий пока нет" Foreground="#5A5D63" FontSize="13" Margin="0,10,0,0" HorizontalAlignment="Center"/>
          </StackPanel>
        </Grid>

        <Grid Grid.Row="5" Margin="0,14,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="120"/></Grid.ColumnDefinitions>
          <Button x:Name="RestoreBtn" Style="{StaticResource MainBtn}" Content="Восстановить"/>
          <Button x:Name="FolderBtn" Grid.Column="1" Style="{StaticResource GhostBtn}" Content="Папка" Margin="10,0,0,0"/>
        </Grid>
      </Grid>

      <!-- настройки -->
      <Grid x:Name="Settings" Visibility="Collapsed" Background="#B3000000" Opacity="0">
        <Border x:Name="SetCard" Background="#1C1D21" CornerRadius="16" Padding="22" Margin="28" VerticalAlignment="Center"
                BorderBrush="#2C2D30" BorderThickness="1" RenderTransformOrigin="0.5,0.5">
          <Border.RenderTransform><ScaleTransform x:Name="SetScale"/></Border.RenderTransform>
          <StackPanel>
            <TextBlock Text="Настройки" Foreground="#D7D8DB" FontSize="18" FontWeight="SemiBold"/>
            <Grid Margin="0,18,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel Margin="0,0,16,0">
                <TextBlock Text="Включать бэкапы при запуске игры" Foreground="#D7D8DB" FontSize="14" TextWrapping="Wrap"/>
                <TextBlock Foreground="#878B91" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="17"
                           Text="Как только запустится R.E.P.O., бэкапы включатся сами. Программа при этом должна быть открыта (можно свернуть)."/>
              </StackPanel>
              <CheckBox x:Name="OptAuto" Grid.Column="1" Style="{StaticResource Toggle}" VerticalAlignment="Center"/>
            </Grid>
            <Button x:Name="SetDone" Style="{StaticResource MainBtn}" Content="Готово" Margin="0,22,0,0"/>
          </StackPanel>
        </Border>
      </Grid>

      <!-- диалог -->
      <Grid x:Name="Dialog" Visibility="Collapsed" Background="#B3000000" Opacity="0">
        <Border x:Name="DlgCard" Background="#1C1D21" CornerRadius="16" Padding="22" Margin="28" VerticalAlignment="Center"
                BorderBrush="#2C2D30" BorderThickness="1" RenderTransformOrigin="0.5,0.5">
          <Border.RenderTransform><ScaleTransform x:Name="DlgScale"/></Border.RenderTransform>
          <StackPanel>
            <TextBlock x:Name="DlgTitle" Foreground="#D7D8DB" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
            <TextBlock x:Name="DlgText" Foreground="#878B91" FontSize="13" TextWrapping="Wrap" Margin="0,8,0,20" LineHeight="19"/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
              <Button x:Name="DlgNo" Style="{StaticResource GhostBtn}" Content="Отмена" Margin="0,0,5,0"/>
              <Button x:Name="DlgYes" Grid.Column="1" Style="{StaticResource MainBtn}" Content="Ок" Margin="5,0,0,0"/>
            </Grid>
          </StackPanel>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'SetBtn','Settings','SetCard','SetScale','OptAuto','SetDone','VerText','BackBtn','SectionTitle','Root','RootShift','RootScale','Header','Dot','MinBtn','CloseBtn','Power','PowerScale','Glow','Ripple','RippleScale',
               'Ring','Arc','ArcRot','PowerIcon','IconScale','StateText','StateShift','SubText','CountText','CleanBtn','List','Empty',
               'RestoreBtn','FolderBtn','Dialog','DlgCard','DlgScale','DlgTitle','DlgText','DlgNo','DlgYes') {
    $ui[$n] = $win.FindName($n)
}

# своя иконка (окно и панель задач)
try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]"$PSScriptRoot\icon.ico") } catch { }

# ---------- анимации ----------
$OP = [Windows.UIElement]::OpacityProperty
$SX = [Windows.Media.ScaleTransform]::ScaleXProperty
$SY = [Windows.Media.ScaleTransform]::ScaleYProperty
$TY = [Windows.Media.TranslateTransform]::YProperty
$easeOut = New-Object Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseOut' }
$easeIn  = New-Object Windows.Media.Animation.CubicEase -Property @{ EasingMode = 'EaseIn' }
$back    = New-Object Windows.Media.Animation.BackEase  -Property @{ EasingMode = 'EaseOut'; Amplitude = 0.5 }
$elastic = New-Object Windows.Media.Animation.ElasticEase -Property @{ EasingMode = 'EaseOut'; Oscillations = 2; Springiness = 5 }

function Anim($obj, $dp, $to, $ms, $from = $null, $ease = $easeOut, $delay = 0, $done = $null) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation
    $a.To = $to
    if ($null -ne $from) { $a.From = $from }
    $a.Duration = [Windows.Duration][TimeSpan]::FromMilliseconds($ms)
    $a.BeginTime = [TimeSpan]::FromMilliseconds($delay)
    if ($ease) { $a.EasingFunction = $ease }
    if ($done) { $a.Add_Completed($done) }
    $obj.BeginAnimation($dp, $a)
}
function Scale($st, $to, $ms, $from = $null, $ease = $easeOut, $delay = 0) {
    Anim $st $SX $to $ms $from $ease $delay; Anim $st $SY $to $ms $from $ease $delay
}
function Brush($hex) { New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)) }
function ColorTo($brush, $hex, $ms = 350) {
    $a = New-Object Windows.Media.Animation.ColorAnimation
    $a.To = [Windows.Media.ColorConverter]::ConvertFromString($hex)
    $a.Duration = [Windows.Duration][TimeSpan]::FromMilliseconds($ms)
    $a.EasingFunction = $easeOut
    $brush.BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty, $a)
}
function Set-TextAnimated($tb, $text, $shift = $null) {
    if ($tb.Text -eq $text) { return }
    $tb.Text = $text
    Anim $tb $OP 1 300 0
    if ($shift) { Anim $shift $TY 0 350 8 }
}

# анимируемые кисти
$ringBrush = Brush "#2C2D30"; $ui.Ring.Stroke = $ringBrush
$iconBrush = Brush "#5A5D63"; $ui.PowerIcon.Foreground = $iconBrush
$dotBrush  = Brush "#3A3B40"; $ui.Dot.Fill = $dotBrush

$pulse = New-Object Windows.Media.Animation.DoubleAnimation(0.18, 0.42, [Windows.Duration]::new([TimeSpan]::FromSeconds(1.8)))
$pulse.AutoReverse = $true
$pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
$pulse.EasingFunction = New-Object Windows.Media.Animation.SineEase -Property @{ EasingMode = 'EaseInOut' }
$pulse.BeginTime = [TimeSpan]::FromMilliseconds(300)

$spin = New-Object Windows.Media.Animation.DoubleAnimation(0, 360, [Windows.Duration]::new([TimeSpan]::FromSeconds(2.4)))
$spin.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever

function Invoke-Ripple {
    Scale $ui.RippleScale 1.5 900 1
    Anim $ui.Ripple $OP 0 900 0.8
}

function Animate-List($delay = 0) {
    $ui.List.UpdateLayout()
    for ($i = 0; $i -lt $ui.List.Items.Count; $i++) {
        $c = $ui.List.ItemContainerGenerator.ContainerFromIndex($i)
        if (-not $c) { continue }
        $tt = New-Object Windows.Media.TranslateTransform 0, 16
        $c.RenderTransform = $tt
        $c.Opacity = 0
        $d = $delay + [Math]::Min($i, 8) * 55
        Anim $c $OP 1 320 0 $easeOut $d
        Anim $tt $TY 0 420 16 $easeOut $d
    }
}

# ---------- логика ----------
# Копирует один сейв. Возвращает $true, если появилась новая копия; при ошибке бросает исключение.
# Копия сначала пишется во временную папку и переименовывается только целиком:
# оборванное копирование не оставит «битую» копию, и на следующей проверке попытка повторится.
function Backup-Save($dir, $trim = $true) {
    $files = Get-ChildItem $dir -Recurse -File -ErrorAction Stop
    if (-not $files) { return $false }
    $stamp  = ($files | Measure-Object LastWriteTime -Maximum).Maximum.ToString("yyyy-MM-dd_HH-mm-ss")
    $target = Join-Path $dst (Split-Path $dir -Leaf)
    $copy   = Join-Path $target $stamp
    if (Test-Path $copy) { return $false }
    $tmp = "$copy.tmp"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    try {
        New-Item -ItemType Directory -Force $tmp | Out-Null
        Copy-Item "$dir\*" $tmp -Recurse -Force -ErrorAction Stop
        Rename-Item $tmp $stamp -ErrorAction Stop
    } catch {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
    if ($trim) {
        Get-ChildItem $target -Directory | Where-Object Name -notlike '*.tmp' | Sort-Object Name -Descending |
            Select-Object -Skip $keep | Remove-Item -Recurse -Force
    }
    return $true
}

function Invoke-Backup {
    $r = @{ New = 0; Failed = 0; Error = $null }
    if (-not (Test-Path $src)) { return $r }
    foreach ($save in Get-ChildItem $src -Directory -Filter "REPO_SAVE_*") {
        try { if (Backup-Save $save.FullName) { $r.New++ } }
        catch { $r.Failed++; $r.Error = $_.Exception.Message }
    }
    return $r
}

# ---------- список: игры (папки) и их копии ----------
# У каждой игры R.E.P.O. своя папка сейва REPO_SAVE_<дата начала>, поэтому каждая новая игра
# автоматически становится новой папкой в списке.
$script:game = $null   # $null = главный экран со списком игр, иначе имя папки открытой игры
$gameNames = @{}       # имя папки сейва -> «Игра #N» (номер по порядку начала игры)

function Get-Plural($n, $one, $few, $many) {
    $a = $n % 10; $b = $n % 100
    if ($a -eq 1 -and $b -ne 11) { $one } elseif ($a -ge 2 -and $a -le 4 -and ($b -lt 12 -or $b -gt 14)) { $few } else { $many }
}
function Format-Ago($stamp) {
    try { $t = [datetime]::ParseExact($stamp, 'yyyy-MM-dd_HH-mm-ss', $null) } catch { return "" }
    $d = (Get-Date) - $t
    if ($d.TotalMinutes -lt 1) { "только что" }
    elseif ($d.TotalHours -lt 1) { "$([int][Math]::Floor($d.TotalMinutes)) мин назад" }
    elseif ($d.TotalDays -lt 1)  { "$([int][Math]::Floor($d.TotalHours)) ч назад" }
    else { $t.ToString("dd.MM.yyyy") }
}

# копии всех игр (или одной), в каждой игре новые сверху
function Get-Copies($save = $null) {
    @(Get-ChildItem $dst -Directory -Filter "REPO_SAVE_*" -ErrorAction SilentlyContinue |
        Where-Object { -not $save -or $_.Name -eq $save } | ForEach-Object {
            $s = $_
            Get-ChildItem $s.FullName -Directory | Where-Object Name -notlike '*.tmp' | ForEach-Object {
                [BackupItem]@{ Kind = 'copy'; Save = $s.Name; Path = $_.FullName
                    Title = $_.Name -replace '^(\d+)-(\d+)-(\d+)_(\d+)-(\d+)-(\d+)$', 'Копия от $3.$2 в $4:$5:$6'
                    Sub = Format-Ago $_.Name; Icon = [string][char]0xE81C; IconColor = '#FBB26A' }
            }
        } | Sort-Object Path -Descending)
}

function Update-List($animate = $true) {
    $all   = Get-Copies
    $saves = @($all | Group-Object Save | Sort-Object Name)
    $i = 0; foreach ($g in $saves) { $i++; $gameNames[$g.Name] = "Игра #$i" }
    if ($script:game -and -not ($saves | Where-Object Name -eq $script:game)) { $script:game = $null }   # игру удалили целиком

    if ($script:game) {
        $items  = @($all | Where-Object Save -eq $script:game)
        $hasOld = $items.Count -gt 1
        $ui.SectionTitle.Text = $gameNames[$script:game]
        $ui.BackBtn.Visibility = 'Visible'
    } else {
        $items = @($saves | Sort-Object Name -Descending | ForEach-Object {
            $alive = Test-Path (Join-Path $src $_.Name)
            $n = $_.Count
            [BackupItem]@{ Kind = 'game'; Title = $gameNames[$_.Name]; Save = $_.Name; Path = Join-Path $dst $_.Name
                Sub = "$n $(Get-Plural $n 'копия' 'копии' 'копий') · " +
                      $(if ($alive) { $_.Name -replace '^REPO_SAVE_(\d+)_(\d+)_(\d+)_(\d+)_(\d+).*$', 'начата $3.$2 в $4:$5' } else { "сейв удалён игрой" })
                Icon = [string][char]0xE8B7; IconColor = $(if ($alive) { '#FBB26A' } else { '#5A5D63' }) }
        })
        $hasOld = [bool]($saves | Where-Object Count -gt 1)
        $ui.SectionTitle.Text = "Игры"
        $ui.BackBtn.Visibility = 'Collapsed'
    }
    $ui.List.ItemsSource = $items
    $ui.Empty.Visibility = if ($items.Count) { 'Collapsed' } else { 'Visible' }
    Set-TextAnimated $ui.CountText $(if ($items.Count) { "$($items.Count) шт." } else { "" })
    $ui.CleanBtn.Visibility = if ($hasOld) { 'Visible' } else { 'Collapsed' }
    if ($animate) { Animate-List }
}

function Open-Game($save) { $script:game = $save; Update-List }

# ---------- удаление копий ----------
function Remove-Copy($path) {
    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    $parent = Split-Path $path
    if ((Test-Path $parent) -and -not (Get-ChildItem $parent -Force)) { Remove-Item $parent -Force }
}

# карточки уезжают вправо и тают, потом выполняется $done
function Animate-Out($items, $done) {
    $hooked = $false
    foreach ($it in $items) {
        $c = $ui.List.ItemContainerGenerator.ContainerFromItem($it)
        if (-not $c) { continue }
        $tt = New-Object Windows.Media.TranslateTransform
        $c.RenderTransform = $tt
        Anim $tt ([Windows.Media.TranslateTransform]::XProperty) 70 280 0 $easeIn
        if (-not $hooked) { Anim $c $OP 0 260 $null $easeIn 0 $done; $hooked = $true }
        else              { Anim $c $OP 0 260 $null $easeIn }
    }
    if (-not $hooked) { & $done }
}

# диалог
$script:dlgOpen = $false
$red = Brush "#FF6B6B"
function Show-Dialog($title, $text, $yesText = "Ок", $action = $null, $danger = $false) {
    if ($danger) { $ui.DlgYes.Background = $red } else { $ui.DlgYes.ClearValue([Windows.Controls.Control]::BackgroundProperty) }
    $ui.DlgTitle.Text = $title
    $ui.DlgText.Text  = $text
    $ui.DlgYes.Content = $yesText
    $ui.DlgYes.Visibility = 'Visible'
    $ui.DlgNo.Visibility = if ($action) { 'Visible' } else { 'Collapsed' }
    [Windows.Controls.Grid]::SetColumn($ui.DlgYes, $(if ($action) { 1 } else { 0 }))
    [Windows.Controls.Grid]::SetColumnSpan($ui.DlgYes, $(if ($action) { 1 } else { 2 }))
    $script:dlgAction = $action
    $script:dlgOpen = $true
    $ui.Dialog.Visibility = 'Visible'
    Anim $ui.Dialog $OP 1 200
    Anim $ui.DlgCard $OP 1 250 0
    Scale $ui.DlgScale 1 380 0.88 $back
}
function Hide-Dialog {
    $script:dlgOpen = $false
    Scale $ui.DlgScale 0.94 160 $null $easeIn
    Anim $ui.Dialog $OP 0 180 $null $easeIn 0 { if (-not $script:dlgOpen) { $ui.Dialog.Visibility = 'Collapsed' } }
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes(1)

$subBrush = $ui.SubText.Foreground
function Reset-SubText { $ui.SubText.Foreground = $subBrush; $ui.SubText.ToolTip = $null }

function Invoke-Tick {
    $r = Invoke-Backup
    $now = Get-Date -Format "HH:mm"
    if ($r.New -gt 0) { Update-List; Invoke-Ripple }
    if ($r.Failed -gt 0) {
        # красный статус с причиной во всплывающей подсказке; через минуту таймер попробует снова
        $ui.SubText.Foreground = $red
        $ui.SubText.ToolTip = $r.Error
        Set-TextAnimated $ui.SubText "⚠ Не удалось скопировать: $($r.Failed) · повторю через минуту"
    } else {
        Reset-SubText
        if ($r.New -gt 0) { Set-TextAnimated $ui.SubText "Новых копий: $($r.New) · проверено в $now" }
        else              { Set-TextAnimated $ui.SubText "Изменений нет · проверено в $now" }
    }
}

function Set-State($on, $instant = $false) {
    $script:on = $on
    if ($on) {
        ColorTo $ringBrush "#FBB26A"; ColorTo $iconBrush "#FBB26A"; ColorTo $dotBrush "#FBB26A"
        Set-TextAnimated $ui.StateText "Бэкапы включены" $ui.StateShift
        $ui.Glow.BeginAnimation($OP, $pulse)
        Anim $ui.Arc $OP 1 500 $null $easeOut 150
        $ui.ArcRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $spin)
        Scale $ui.IconScale 1 600 0.7 $elastic
        Invoke-Ripple
        $timer.Start()
        Invoke-Tick
    } else {
        $timer.Stop()
        ColorTo $ringBrush "#2C2D30"; ColorTo $iconBrush "#5A5D63"; ColorTo $dotBrush "#3A3B40"
        Anim $ui.Glow $OP 0 400
        Anim $ui.Arc $OP 0 250 $null $easeOut 0 { if (-not $script:on) { $ui.ArcRot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null) } }
        if (-not $instant) { Scale $ui.IconScale 1 450 0.85 $back }
        Set-TextAnimated $ui.StateText "Бэкапы выключены" $ui.StateShift
        Reset-SubText
        Set-TextAnimated $ui.SubText "Нажми на кнопку, чтобы включить"
    }
}

# ---------- события ----------
$timer.Add_Tick({ Invoke-Tick })
$ui.Header.Add_MouseLeftButtonDown({ $win.DragMove() })
$ui.MinBtn.Add_Click({ Minimize-Animated })
$ui.CloseBtn.Add_Click({ $win.Close() })

# кнопка питания: сжимается при нажатии и пружинит обратно
$ui.Power.Add_MouseLeftButtonDown({ $script:pressed = $true; Scale $ui.PowerScale 0.92 120 })
$ui.Power.Add_MouseLeftButtonUp({
    if (-not $script:pressed) { return }
    $script:pressed = $false
    Scale $ui.PowerScale 1 650 $null $elastic
    Set-State (-not $script:on)
})
$ui.Power.Add_MouseEnter({ if (-not $script:on) { ColorTo $ringBrush "#45464C" 200; ColorTo $iconBrush "#878B91" 200 } })
$ui.Power.Add_MouseLeave({
    if ($script:pressed) { $script:pressed = $false; Scale $ui.PowerScale 1 400 $null $back }
    if (-not $script:on) { ColorTo $ringBrush "#2C2D30" 300; ColorTo $iconBrush "#5A5D63" 300 }
})

$ui.FolderBtn.Add_Click({ New-Item -ItemType Directory -Force $dst | Out-Null; Start-Process explorer.exe $dst })
$ui.DlgNo.Add_Click({ Hide-Dialog })
$ui.SetBtn.Add_Click({ Show-Settings })
$ui.SetDone.Add_Click({ Hide-Settings })
# клик по затемнённому фону тоже закрывает настройки
$ui.Settings.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $ui.Settings) { Hide-Settings } })
$ui.OptAuto.Add_Click({ $settings.AutoStart = [bool]$ui.OptAuto.IsChecked; Save-Settings })

$ui.DlgYes.Add_Click({
    Hide-Dialog
    $a = $script:dlgAction; $script:dlgAction = $null
    if ($a) { & $a }
})

$ui.RestoreBtn.Add_Click({
    $pick = $ui.List.SelectedItem
    if (-not $pick -or $pick.Kind -ne 'copy') {
        $hint = if ($script:game) { "Нажми на нужную копию в списке, потом на «Восстановить»." } else { "Открой игру в списке и выбери в ней копию." }
        Show-Dialog "Выбери копию" $hint; return
    }
    $script:pick = $pick
    Show-Dialog "Восстановить сейв?" "$($gameNames[$pick.Save]) · $($pick.Title)`n`nТекущий сейв этой игры (если он есть) будет заменён копией. Перед этим он сам сохранится в список копий." "Восстановить" {
        Start-Restore $script:pick
    }
})

# ---------- восстановление ----------
# Возвращает $null при успехе или текст ошибки.
function Restore-Copy($item) {
    $out = Join-Path $src $item.Save
    # страховка: сначала копируем текущий сейв, чтобы откат можно было отменить
    if (Test-Path $out) {
        try { [void](Backup-Save $out $false) }   # без ротации: иначе могла бы удалиться восстанавливаемая копия
        catch { return "Не удалось сохранить копию текущего сейва, поэтому восстановление отменено.`n`n$($_.Exception.Message)" }
    }
    try {
        if (Test-Path $out) { Remove-Item $out -Recurse -Force }
        New-Item -ItemType Directory -Force $out | Out-Null
        Copy-Item "$($item.Path)\*" $out -Recurse -Force -ErrorAction Stop
        $script:known[$item.Save] = $true
        return $null
    } catch { return $_.Exception.Message }
}

# Пока игра запущена, сейв не трогаем: восстановим сами, как только её закроют.
$script:pending = $null
function Start-Restore($item) {
    if (Get-Process -Name "REPO" -ErrorAction SilentlyContinue) {
        $script:pending = $item
        Show-Dialog "Закрой игру" "Пока R.E.P.O. запущена, сейв трогать нельзя.`n`nПросто выйди из игры: $($gameNames[$item.Save]) восстановится сама, как только игра закроется."
        return
    }
    $had = Test-Path (Join-Path $src $item.Save)
    $err = Restore-Copy $item
    Update-List $false
    if ($err) { Show-Dialog "Ошибка" $err; return }
    $text = "$($gameNames[$item.Save]) снова в списке сохранений игры."
    Show-Dialog "Готово!" ("Сейв восстановлен. $text" + $(if ($had) { "`n`nПрежний сейв сохранён в списке копий, если захочешь вернуть его." } else { "" }))
    if (-not $win.IsActive) { Notify "Сейв восстановлен" "$text Можно запускать R.E.P.O." 'Info' }
}

# ---------- гибель команды ----------
# Когда вся команда погибает, игра удаляет папку сейва. Раз в 3 секунды сверяем папки с прошлой проверкой.
$script:known   = @{}   # сейвы, которые были в папке игры
$script:missing = @{}   # пропали на прошлой проверке: ждём ещё одну, чтобы не сработать на перезаписи файла
$script:lastSig = $null; $script:dirty = $false
# «отпечаток» всех файлов сейвов: путь, время изменения, размер
function Get-SavesSignature {
    (Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue | Where-Object FullName -like '*\REPO_SAVE_*' |
        ForEach-Object { "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$($_.Length)" }) -join ';'
}
function Get-GameSaves { @(Get-ChildItem $src -Directory -Filter "REPO_SAVE_*" -ErrorAction SilentlyContinue | ForEach-Object Name) }

# ---------- настройки ----------
# хранятся рядом с программой; если файла нет или он битый — значения по умолчанию
$settingsPath = "$PSScriptRoot\settings.json"
$settings = [pscustomobject]@{ AutoStart = $true }
try {
    $loaded = Get-Content $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($null -ne $loaded.AutoStart) { $settings.AutoStart = [bool]$loaded.AutoStart }
} catch { }
function Save-Settings { try { $settings | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8 } catch { } }

function Show-Settings {
    $ui.OptAuto.IsChecked = $settings.AutoStart
    $ui.Settings.Visibility = 'Visible'
    Anim $ui.Settings $OP 1 200
    Scale $ui.SetScale 1 380 0.88 $back
}
function Hide-Settings {
    Scale $ui.SetScale 0.94 160 $null $easeIn
    Anim $ui.Settings $OP 0 180 $null $easeIn 0 { $ui.Settings.Visibility = 'Collapsed' }
}

# автовключение: ловим момент, когда игра запустилась (была закрыта -> стала запущена).
# Если игрок сам выключил бэкапы во время игры, повторно не включаем до следующего запуска игры.
$script:gameWasRunning = $false
function Invoke-AutoStart($running) {
    if ($running -and -not $script:gameWasRunning -and $settings.AutoStart -and -not $script:on) {
        Set-State $true
        $script:lastSig = Get-SavesSignature; $script:dirty = $false   # бэкап только что сделан, лишний не нужен
        Set-TextAnimated $ui.SubText "Включено автоматически: запущена R.E.P.O."
        if (-not $win.IsActive) { Notify "Бэкапы включены" "Запущена R.E.P.O., сейвы сохраняются автоматически." 'Info' }
    }
    $script:gameWasRunning = $running
}

function Invoke-Watch {
    Invoke-AutoStart ([bool](Get-Process -Name "REPO" -ErrorAction SilentlyContinue))
    $now = Get-GameSaves
    foreach ($n in @($script:known.Keys)) {
        if ($now -contains $n) { $script:missing.Remove($n); continue }
        if (-not $script:missing[$n]) { $script:missing[$n] = $true; continue }
        $script:known.Remove($n); $script:missing.Remove($n)
        $last = Get-Copies $n | Select-Object -First 1
        if ($last) { Show-WipeAlert $last }
    }
    foreach ($n in $now) { $script:known[$n] = $true }
    # копия сразу после сохранения: игра что-то записала -> ждём, пока файлы перестанут меняться
    # (одна проверка без изменений), и копируем. Итого 3–6 секунд после сохранения.
    if ($script:on) {
        $sig = Get-SavesSignature
        if ($sig -ne $script:lastSig) { $script:lastSig = $sig; $script:dirty = $true }
        elseif ($script:dirty) { $script:dirty = $false; Invoke-Tick }
    }
    # отложенное восстановление: игру закрыли
    if ($script:pending -and -not (Get-Process -Name "REPO" -ErrorAction SilentlyContinue)) {
        $p = $script:pending; $script:pending = $null
        Start-Restore $p
    }
}

function Show-WipeAlert($item) {
    Update-List $false
    $name = $gameNames[$item.Save]
    $script:wipeItem = $item
    Notify "Сейв удалён" "${name}: похоже, команда погибла. Открой R.E.P.O. Backup, чтобы восстановить последнюю копию." 'Warning'
    Show-Dialog "Сейв удалён" ("Похоже, команда погибла, и игра удалила сейв «$name».`n`n" +
        "Восстановить последнюю копию ($($item.Title.ToLower()))?`n`nЕсли ты удалил сейв сам, просто нажми «Отмена».") "Восстановить" {
        Start-Restore $script:wipeItem
    }
}

# всплывающее уведомление Windows (окно может быть свёрнуто, а игрок в игре)
Add-Type -AssemblyName System.Windows.Forms
$tray = New-Object Windows.Forms.NotifyIcon
try { $tray.Icon = New-Object Drawing.Icon "$PSScriptRoot\icon.ico" } catch { $tray.Icon = [Drawing.SystemIcons]::Information }
$tray.Text = "R.E.P.O. Backup"
function Show-Window {
    $tray.Visible = $false
    if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
    [void]$win.Activate()
}
$tray.Add_BalloonTipClicked({ Show-Window })
$tray.Add_MouseClick({ Show-Window })
$tray.Add_BalloonTipClosed({ $tray.Visible = $false })
function Notify($title, $text, $icon = 'Info') {
    $tray.Visible = $true
    $tray.ShowBalloonTip(10000, $title, $text, [Windows.Forms.ToolTipIcon]$icon)
}

$watch = New-Object Windows.Threading.DispatcherTimer
$watch.Interval = [TimeSpan]::FromSeconds(3)
$watch.Add_Tick({ Invoke-Watch })

# ---------- навигация и удаление ----------
# клик по игре открывает её копии
$ui.List.Add_SelectionChanged({
    $it = $ui.List.SelectedItem
    if ($it -and $it.Kind -eq 'game') { $script:openSave = $it.Save; [void]$win.Dispatcher.BeginInvoke([Action]{ Open-Game $script:openSave }) }
})
$ui.BackBtn.Add_Click({ $script:game = $null; Update-List })

# крестик на карточке: удалить копию или всю игру
$ui.List.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
    param($s, $e)
    $b = $e.OriginalSource
    if ($b.Name -ne 'DelBtn') { return }
    $e.Handled = $true
    $script:delItem = $b.Tag
    if ($b.Tag.Kind -eq 'game') {
        Show-Dialog "Удалить игру?" "$($b.Tag.Title)`n$($b.Tag.Sub)`n`nВсе копии этой игры будут удалены навсегда. Сам сейв в игре не тронется." "Удалить" {
            Animate-Out @($script:delItem) { Remove-Item $script:delItem.Path -Recurse -Force -ErrorAction SilentlyContinue; Update-List $false }
        } $true
    } else {
        Show-Dialog "Удалить копию?" "$($gameNames[$b.Tag.Save]) · $($b.Tag.Title)`n`nКопия будет удалена навсегда." "Удалить" {
            Animate-Out @($script:delItem) { Remove-Copy $script:delItem.Path; Update-List $false }
        } $true
    }
})

# «Очистить старые»: у каждой игры (или у открытой) остаётся только самая свежая копия
$ui.CleanBtn.Add_Click({
    $old = @(Get-Copies $script:game | Group-Object Save | ForEach-Object { $_.Group | Select-Object -Skip 1 })
    if (-not $old.Count) { return }
    $script:delItems = $old
    $who = if ($script:game) { "У этой игры" } else { "У каждой игры" }
    Show-Dialog "Очистить старые копии?" "$who останется только самая свежая копия.`nБудет удалено копий: $($old.Count)." "Удалить" {
        # анимируем только видимые карточки (на главном экране это игры, а не копии)
        Animate-Out @($ui.List.ItemsSource | Where-Object Kind -eq 'copy' | Where-Object { $p = $_.Path; $script:delItems | Where-Object Path -eq $p }) {
            foreach ($i in $script:delItems) { Remove-Copy $i.Path }; Update-List
        }
    } $true
})

# появление окна
$win.Add_Loaded({
    Anim $ui.Root $OP 1 380
    Anim $ui.RootShift $TY 0 480 24
    Scale $ui.RootScale 1 480 0.96
    Scale $ui.PowerScale 1 700 0.85 $back 120
    Animate-List 250
})

# сворачивание: окно сжимается, уходит вниз и тает, потом сворачивается
$script:minimizing = $false
function Minimize-Animated {
    if ($script:minimizing) { return }
    $script:minimizing = $true
    Scale $ui.RootScale 0.86 230 $null $easeIn
    Anim $ui.RootShift $TY 60 230 $null $easeIn
    Anim $ui.Root $OP 0 210 $null $easeIn 0 {
        $win.WindowState = 'Minimized'
        $script:minimizing = $false
    }
}
# разворачивание: окно выпрыгивает обратно с лёгким отскоком
$win.Add_StateChanged({
    if ($win.WindowState -eq 'Normal') {
        Anim $ui.Root $OP 1 260 0
        Scale $ui.RootScale 1 420 0.86 $back
        Anim $ui.RootShift $TY 0 420 60
    }
})
$win.Add_SourceInitialized({
    [MinHook]::OnMinimize = [Action]{ Minimize-Animated }
    [MinHook]::Attach($win)
})

# плавное исчезновение при закрытии (в том числе по Alt+F4)
$script:closing = $false
$win.Add_Closing({
    param($s, $e)
    if ($script:closing) { return }
    $e.Cancel = $true
    $script:closing = $true
    $timer.Stop(); $watch.Stop()
    $tray.Visible = $false; $tray.Dispose()
    Scale $ui.RootScale 0.94 220 $null $easeIn
    Anim $ui.RootShift $TY 16 220 $null $easeIn
    Anim $ui.Root $OP 0 220 $null $easeIn 0 { $win.Close() }
})

$ui.StateText.Text = "Бэкапы выключены"
$ui.SubText.Text = "Нажми на кнопку, чтобы включить"
$script:on = $false
Update-List $false
foreach ($n in Get-GameSaves) { $script:known[$n] = $true }
$watch.Start()

# ---------- обновления ----------
$repo = "TiSkill/repo-backup"
$installed = Test-Path "$PSScriptRoot\unins000.exe"   # поставлено установщиком, а не распаковано из zip
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ui.VerText.Text = "v$AppVersion"

# диалог без кнопок (пока что-то идёт)
function Show-Busy($title, $text) { Show-Dialog $title $text; $ui.DlgYes.Visibility = 'Collapsed' }

# Ждёт фоновую задачу, не подвешивая окно: проверяет раз в 300 мс, потом вызывает $done с задачей.
# (Код PowerShell при этом выполняется только в потоке окна.)
function Wait-Task($task, $done) {
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(300)
    $t.Tag = @{ Task = $task; Done = $done }
    $t.Add_Tick({ param($s) if ($s.Tag.Task.IsCompleted) { $s.Stop(); & $s.Tag.Done $s.Tag.Task } })
    $t.Start()
}
function New-WebClient {
    $c = New-Object Net.WebClient
    $c.Headers['User-Agent'] = 'REPO-Backup'
    $c.Encoding = [Text.Encoding]::UTF8
    $c
}

function Check-Update($manual = $false) {
    $script:manualCheck = $manual
    $c = New-WebClient
    $c.Headers['Accept'] = 'application/vnd.github+json'
    $task = $c.DownloadStringTaskAsync("https://api.github.com/repos/$repo/releases/latest")
    Wait-Task $task {
        param($task)
        if ($task.IsFaulted) {
            if ($script:manualCheck) { Show-Dialog "Не удалось проверить" "Нет связи с GitHub. Попробуй позже." }
            return
        }
        try { $rel = $task.Result | ConvertFrom-Json; $latest = [version]($rel.tag_name.TrimStart('v')) } catch { return }
        if ($latest -le [version]$AppVersion) {
            if ($script:manualCheck) { Show-Dialog "Обновлений нет" "У тебя последняя версия: $AppVersion." }
            return
        }
        if ($script:dlgOpen -and -not $script:manualCheck) { return }   # не перебиваем другой диалог (например, о вайпе)
        $script:update = $rel
        # из описания релиза берём только пункты списка изменений (строки «- …»), без инструкций по установке
        $notes = (($rel.body -replace '\*\*', '' -replace '`', '') -split '\r?\n' | Where-Object { $_ -match '^\s*[-*] ' } |
            Select-Object -First 4 | ForEach-Object { '• ' + ($_ -replace '^\s*[-*] ', '').Trim() }) -join "`n"
        if ($notes.Length -gt 400) { $notes = $notes.Substring(0, 400).TrimEnd() + '…' }
        $yes = if ($installed) { "Обновить" } else { "Скачать" }
        Show-Dialog "Вышла версия $latest" "У тебя $AppVersion.`n`n$notes" $yes { Start-Update }
    }
}

function Start-Update {
    $rel = $script:update
    $asset = $rel.assets | Where-Object name -eq 'REPO-Backup-Setup.exe' | Select-Object -First 1
    # запущено из zip или в релизе нет установщика: просто открываем страницу релиза
    if (-not $installed -or -not $asset) { Start-Process $rel.html_url; return }
    $script:setupPath = Join-Path $env:TEMP "REPO-Backup-Setup-$($rel.tag_name).exe"
    $script:setupSize = $asset.size
    Show-Busy "Скачиваю обновление…" "Версия $($rel.tag_name.TrimStart('v')). Это займёт несколько секунд, потом программа перезапустится."
    $task = (New-WebClient).DownloadFileTaskAsync($asset.browser_download_url, $script:setupPath)
    Wait-Task $task {
        param($task)
        $f = Get-Item $script:setupPath -ErrorAction SilentlyContinue
        if ($task.IsFaulted -or -not $f -or $f.Length -ne $script:setupSize) {
            Show-Dialog "Не удалось скачать" "Попробуй позже или скачай установщик со страницы релиза." "Открыть страницу" { Start-Process $script:update.html_url }
            return
        }
        # ставим поверх; установщик сам запустит новую версию
        Start-Process $script:setupPath -ArgumentList '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/LANG=ru'
        $win.Close()
    }
}

# клик по версии в шапке: проверить вручную (Handled — чтобы шапка не начала перетаскивать окно)
$ui.VerText.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true; Check-Update $true })
# автоматическая проверка через 3 секунды после запуска
$updTimer = New-Object Windows.Threading.DispatcherTimer
$updTimer.Interval = [TimeSpan]::FromSeconds(3)
$updTimer.Add_Tick({ $updTimer.Stop(); Check-Update })
$updTimer.Start()
[void]$win.ShowDialog()
