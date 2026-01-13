using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TalkTime.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class UserDescription : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Description",
                table: "users",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Description",
                table: "users");
        }
    }
}
