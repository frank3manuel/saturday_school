# The single transactional email for the password-reset flow (plan §7). The
# reset token is generated here (expiring, salt-bound via the User model) so the
# controller never has to thread it through.
class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user  = user
    @token = user.generate_token_for(:password_reset)
    mail subject: "Reset your Saturday School password", to: user.email_address
  end
end
