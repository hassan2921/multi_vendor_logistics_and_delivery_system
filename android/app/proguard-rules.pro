# flutter_stripe pulls in react-native-stripe-sdk's push-provisioning (Apple/
# Google Pay push-to-wallet) code path, which this app doesn't use. R8 still
# trips over the missing optional classes it references, so suppress.
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$g
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Args
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Error
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider
