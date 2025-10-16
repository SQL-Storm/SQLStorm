-- {"query": "19.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 409} 
WITH RankedUsers AS (
    SELECT
        Id,
        Reputation,
        CreationDate,
        DisplayName,
        LastAccessDate,
        WebsiteUrl,
        Location,
        AboutMe,
        Views,
        UpVotes,
        DownVotes,
        ProfileImageUrl,
        EmailHash,
        AccountId,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS UserRank
    FROM Users
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.OwnerUserId,
        p.LastActivityDate,
        p.Tags,
        COALESCE(pc.CommentCount, 0) AS CommentCount
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) pc ON p.Id = pc.PostId
    WHERE p.PostTypeId = 1
),
UserRanking AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        up.CreationDate AS UserCreationDate,
        up.Views AS UserViews,
        up.UserRank,
        p.Id AS PostId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.Title AS PostTitle,
        p.LastActivityDate AS LastActivityDate,
        p.Tags AS PostTags,
        p.CommentCount
    FROM RankedUsers u
    JOIN FilteredPosts p ON u.Id = p.OwnerUserId
    JOIN Users up ON u.Id = up.Id
)
SELECT
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.UserCreationDate,
    ur.UserViews,
    ur.UserRank,
    ur.PostId,
    ur.PostCreationDate,
    ur.PostScore,
    ur.PostTitle,
    ur.LastActivityDate,
    ur.PostTags,
    ur.CommentCount
FROM UserRanking ur
WHERE ur.UserRank <= 100
ORDER BY ur.UserRank;