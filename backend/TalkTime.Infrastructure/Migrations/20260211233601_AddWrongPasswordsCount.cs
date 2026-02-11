using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TalkTime.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddWrongPasswordsCount : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "wrong_password_date",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "wrong_passwords_count",
                table: "users",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "wrong_password_date",
                table: "users");

            migrationBuilder.DropColumn(
                name: "wrong_passwords_count",
                table: "users");
        }
    }
}
