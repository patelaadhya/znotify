# WinRT Toast Notification Interfaces

This document extracts the key COM interfaces and GUIDs needed for direct WinRT toast notifications from the Windows SDK ABI headers.

## Required Interfaces

### 1. IXmlDocumentIO - Load XML String

**GUID:** `{6cd0e74e-ee65-4489-9ebf-ca43e87ba637}`
**Runtime Class:** `Windows.Data.Xml.Dom.XmlDocument`
**Header:** `windows.data.xml.dom.h`

```cpp
MIDL_INTERFACE("6cd0e74e-ee65-4489-9ebf-ca43e87ba637")
IXmlDocumentIO : public IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE LoadXml(HSTRING xml) = 0;
    virtual HRESULT STDMETHODCALLTYPE LoadXmlWithSettings(
        HSTRING xml,
        IXmlLoadSettings* loadSettings) = 0;
    virtual HRESULT STDMETHODCALLTYPE SaveToFileAsync(
        IStorageFile* file,
        IAsyncAction** asyncInfo) = 0;
};
```

**Methods we need:**
- `LoadXml(HSTRING xml)` - Load toast XML string

---

### 2. IToastNotificationFactory - Create Toast from XML

**GUID:** `{04124b20-82c6-4229-b109-fd9ed4662b53}`
**Runtime Class:** `Windows.UI.Notifications.ToastNotification`
**Header:** `windows.ui.notifications.h`

```cpp
MIDL_INTERFACE("04124b20-82c6-4229-b109-fd9ed4662b53")
IToastNotificationFactory : public IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE CreateToastNotification(
        ABI::Windows::Data::Xml::Dom::IXmlDocument* content,
        ABI::Windows::UI::Notifications::IToastNotification** value) = 0;
};
```

**Methods we need:**
- `CreateToastNotification(IXmlDocument*, IToastNotification**)` - Create toast from XML document

---

### 3. IToastNotification - Toast Object

**GUID:** `{997e2675-059e-4e60-8b06-1760917c8b80}`
**Runtime Class:** `Windows.UI.Notifications.ToastNotification`
**Header:** `windows.ui.notifications.h`

```cpp
MIDL_INTERFACE("997e2675-059e-4e60-8b06-1760917c8b80")
IToastNotification : public IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Content(IXmlDocument** value) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_ExpirationTime(__FIReference_1_DateTime* value) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_ExpirationTime(__FIReference_1_DateTime** value) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_Dismissed(/* event handler */) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_Dismissed(EventRegistrationToken token) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_Activated(/* event handler */) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_Activated(EventRegistrationToken token) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_Failed(/* event handler */) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_Failed(EventRegistrationToken token) = 0;
};
```

**Methods we need:**
- None directly - this is the notification object we pass to IToastNotifier.Show()

---

### 4. IToastNotificationManagerStatics - Get Notifier with AUMID

**GUID:** `{50ac103f-d235-4598-bbef-98fe4d1a3ad4}`
**Runtime Class:** `Windows.UI.Notifications.ToastNotificationManager`
**Header:** `windows.ui.notifications.h`

```cpp
MIDL_INTERFACE("50ac103f-d235-4598-bbef-98fe4d1a3ad4")
IToastNotificationManagerStatics : public IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE CreateToastNotifier(
        IToastNotifier** result) = 0;
    virtual HRESULT STDMETHODCALLTYPE CreateToastNotifierWithId(
        HSTRING applicationId,
        IToastNotifier** result) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetTemplateContent(
        ToastTemplateType type,
        IXmlDocument** result) = 0;
};
```

**Methods we need:**
- `CreateToastNotifierWithId(HSTRING aumid, IToastNotifier**)` - Get notifier for our AUMID

---

### 5. IToastNotifier - Show Notification

**GUID:** `{75927b93-03f3-41ec-91d3-6e5bac1b38e7}`
**Runtime Class:** `Windows.UI.Notifications.ToastNotifier`
**Header:** `windows.ui.notifications.h`

```cpp
MIDL_INTERFACE("75927b93-03f3-41ec-91d3-6e5bac1b38e7")
IToastNotifier : public IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE Show(
        IToastNotification* notification) = 0;
    virtual HRESULT STDMETHODCALLTYPE Hide(
        IToastNotification* notification) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Setting(
        NotificationSetting* value) = 0;
    virtual HRESULT STDMETHODCALLTYPE AddToSchedule(
        IScheduledToastNotification* scheduledToast) = 0;
    virtual HRESULT STDMETHODCALLTYPE RemoveFromSchedule(
        IScheduledToastNotification* scheduledToast) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetScheduledToastNotifications(
        __FIVectorView_1_ScheduledToastNotification** result) = 0;
};
```

**Methods we need:**
- `Show(IToastNotification*)` - Display the toast notification

---

## Runtime Class Names

For `RoGetActivationFactory` calls:

```cpp
const wchar_t* CLASS_XmlDocument = L"Windows.Data.Xml.Dom.XmlDocument";
const wchar_t* CLASS_ToastNotification = L"Windows.UI.Notifications.ToastNotification";
const wchar_t* CLASS_ToastNotificationManager = L"Windows.UI.Notifications.ToastNotificationManager";
```

---

## Call Flow

```
1. RoGetActivationFactory(CLASS_XmlDocument, IID_IActivationFactory, &xmlFactory)
2. xmlFactory->ActivateInstance(&xmlDocObj)
3. xmlDocObj->QueryInterface(IID_IXmlDocumentIO, &xmlDoc)
4. xmlDoc->LoadXml(xmlHString)

5. RoGetActivationFactory(CLASS_ToastNotification, IID_IToastNotificationFactory, &toastFactory)
6. toastFactory->CreateToastNotification(xmlDoc, &toast)

7. RoGetActivationFactory(CLASS_ToastNotificationManager, IID_IToastNotificationManagerStatics, &managerStatics)
8. managerStatics->CreateToastNotifierWithId(aumidHString, &notifier)

9. notifier->Show(toast)

10. Release all COM objects in reverse order
11. WindowsDeleteString for all HSTRINGs
```

---

## WinRT Helper Functions Needed

### From combase.dll:
- `RoGetActivationFactory(HSTRING, REFIID, void**)` - Get factory for runtime class
- `RoActivateInstance(HSTRING, IInspectable**)` - Alternative activation method
- `WindowsCreateString(const wchar_t*, UINT32, HSTRING*)` - Create HSTRING from UTF-16
- `WindowsDeleteString(HSTRING)` - Free HSTRING
- `WindowsGetStringRawBuffer(HSTRING, UINT32*)` - Get raw buffer from HSTRING

### Standard COM (ole32.dll):
- Already have `CoInitializeEx` and `CoUninitialize`

---

## IInspectable Base Interface

All WinRT interfaces inherit from `IInspectable`, which inherits from `IUnknown`:

```cpp
IUnknown:
  QueryInterface(REFIID, void**)
  AddRef()
  Release()

IInspectable : IUnknown:
  GetIids(ULONG*, IID**)
  GetRuntimeClassName(HSTRING*)
  GetTrustLevel(TrustLevel*)
```

**VTable offsets:**
- IUnknown methods: 0-2
- IInspectable methods: 3-5
- Interface-specific methods: 6+

---

## Next Steps for Implementation

1. ✅ Extract GUIDs and interface definitions (DONE)
2. Create Zig vtable structures matching these interfaces
3. Implement HSTRING helper functions
4. Implement `RoGetActivationFactory` wrapper
5. Implement `showToastDirect()` following the call flow above
6. Test with simple notification
7. Add error handling and fallback to PowerShell
8. Performance benchmarks

---

## References

- Windows SDK ABI Headers: `C:\Program Files (x86)\Windows Kits\10\Include\[version]\winrt\`
- WinRT Documentation: https://docs.microsoft.com/en-us/windows/uwp/winrt-components/
- C++/WinRT Interop: See `docs/reference/interop-winrt-abi.md`
