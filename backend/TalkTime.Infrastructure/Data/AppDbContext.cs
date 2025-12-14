using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Enums;

namespace TalkTime.Infrastructure.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<Conversation> Conversations => Set<Conversation>();
    public DbSet<ConversationParticipant> ConversationParticipants => Set<ConversationParticipant>();
    public DbSet<Message> Messages => Set<Message>();
    public DbSet<MessageDelivery> MessageDeliveries => Set<MessageDelivery>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // User configuration
        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("users");

            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");

            entity.Property(e => e.Username)
                .HasColumnName("username")
                .HasMaxLength(50)
                .IsRequired();

            entity.Property(e => e.Email)
                .HasColumnName("email")
                .HasMaxLength(255)
                .IsRequired();

            entity.Property(e => e.PasswordHash)
                .HasColumnName("password_hash")
                .IsRequired();

            entity.Property(e => e.AvatarUrl)
                .HasColumnName("avatar_url")
                .HasMaxLength(500);

            entity.Property(e => e.IsOnline)
                .HasColumnName("is_online")
                .HasDefaultValue(false);

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("CURRENT_TIMESTAMP");

            entity.Property(e => e.LastSeenAt)
                .HasColumnName("last_seen_at");

            // Indexes
            entity.HasIndex(e => e.Email).IsUnique();
            entity.HasIndex(e => e.Username).IsUnique();
        });

        // Conversation configuration
        modelBuilder.Entity<Conversation>(entity =>
        {
            entity.ToTable("conversations");

            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");

            entity.Property(e => e.Type)
                .HasColumnName("type")
                .HasConversion<string>()
                .HasMaxLength(20)
                .IsRequired();

            entity.Property(e => e.Name)
                .HasColumnName("name")
                .HasMaxLength(100);

            entity.Property(e => e.CreatedAt)
                .HasColumnName("created_at")
                .HasDefaultValueSql("CURRENT_TIMESTAMP");

            entity.Property(e => e.UpdatedAt)
                .HasColumnName("updated_at");
        });

        // ConversationParticipant configuration (join table)
        modelBuilder.Entity<ConversationParticipant>(entity =>
        {
            entity.ToTable("conversation_participants");

            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");

            entity.Property(e => e.UserId)
                .HasColumnName("user_id")
                .IsRequired();

            entity.Property(e => e.ConversationId)
                .HasColumnName("conversation_id")
                .IsRequired();

            entity.Property(e => e.JoinedAt)
                .HasColumnName("joined_at")
                .HasDefaultValueSql("CURRENT_TIMESTAMP");

            entity.Property(e => e.IsAdmin)
                .HasColumnName("is_admin")
                .HasDefaultValue(false);

            // Relationships
            entity.HasOne(e => e.User)
                .WithMany(u => u.ConversationParticipants)
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.Conversation)
                .WithMany(c => c.Participants)
                .HasForeignKey(e => e.ConversationId)
                .OnDelete(DeleteBehavior.Cascade);

            // Indexes
            entity.HasIndex(e => new { e.ConversationId, e.UserId }).IsUnique();
            entity.HasIndex(e => e.UserId);
        });

        // Message configuration
        modelBuilder.Entity<Message>(entity =>
        {
            entity.ToTable("messages");

            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");

            entity.Property(e => e.ConversationId)
                .HasColumnName("conversation_id")
                .IsRequired();

            entity.Property(e => e.SenderId)
                .HasColumnName("sender_id")
                .IsRequired();

            entity.Property(e => e.EncryptedContent)
                .HasColumnName("encrypted_content")
                .IsRequired();

            entity.Property(e => e.Type)
                .HasColumnName("type")
                .HasConversion<string>()
                .HasMaxLength(20)
                .HasDefaultValue(MessageType.Text);

            entity.Property(e => e.SentAt)
                .HasColumnName("sent_at")
                .HasDefaultValueSql("CURRENT_TIMESTAMP");

            // Relationships
            entity.HasOne(e => e.Conversation)
                .WithMany(c => c.Messages)
                .HasForeignKey(e => e.ConversationId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.Sender)
                .WithMany(u => u.SentMessages)
                .HasForeignKey(e => e.SenderId)
                .OnDelete(DeleteBehavior.Cascade);

            // Indexes
            entity.HasIndex(e => e.ConversationId);
            entity.HasIndex(e => e.SenderId);
            entity.HasIndex(e => e.SentAt);
        });

        // MessageDelivery configuration
        modelBuilder.Entity<MessageDelivery>(entity =>
        {
            entity.ToTable("message_deliveries");

            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");

            entity.Property(e => e.MessageId)
                .HasColumnName("message_id")
                .IsRequired();

            entity.Property(e => e.RecipientId)
                .HasColumnName("recipient_id")
                .IsRequired();

            entity.Property(e => e.IsDelivered)
                .HasColumnName("is_delivered")
                .HasDefaultValue(false);

            entity.Property(e => e.DeliveredAt)
                .HasColumnName("delivered_at");

            // Relationships
            entity.HasOne(e => e.Message)
                .WithMany(m => m.Deliveries)
                .HasForeignKey(e => e.MessageId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(e => e.Recipient)
                .WithMany()
                .HasForeignKey(e => e.RecipientId)
                .OnDelete(DeleteBehavior.Cascade);

            // Indexes
            entity.HasIndex(e => new { e.MessageId, e.RecipientId }).IsUnique();
            entity.HasIndex(e => e.RecipientId);
            entity.HasIndex(e => e.IsDelivered);
        });
    }
}
