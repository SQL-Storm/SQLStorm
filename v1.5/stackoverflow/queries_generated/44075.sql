-- {"query": "44075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 711}

SELECT 
    u.DisplayName AS UserName, 
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass,
    p.Title AS PostTitle,
    p.Body AS PostBody,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS PostAnswerCount,
    p.CommentCount AS PostCommentCount,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        ELSE pt.Name
    END AS PostType,
    COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '') AS PostTags,
    COALESCE(u2.DisplayName, p.OwnerDisplayName) AS PostAuthor,
    COALESCE(u2.Reputation, u.Reputation) AS PostAuthorReputation,
    COALESCE(u2.Location, u.Location) AS PostAuthorLocation,
    COALESCE(u2.AboutMe, u.AboutMe) AS PostAuthorAboutMe,
    COALESCE(u2.WebsiteUrl, u.WebsiteUrl) AS PostAuthorWebsite,
    COALESCE(u2.ProfileImageUrl, u.ProfileImageUrl) AS PostAuthorProfileImage,
    COALESCE(u2.EmailHash, u.EmailHash) AS PostAuthorEmailHash,
    COALESCE(u2.AccountId, u.AccountId) AS PostAuthorAccountId,
    COALESCE(u2.Views, u.Views) AS PostAuthorViews,
    COALESCE(u2.UpVotes, u.UpVotes) AS PostAuthorUpVotes,
    COALESCE(u2.DownVotes, u.DownVotes) AS PostAuthorDownVotes,
    COALESCE(u2.CreationDate, u.CreationDate) AS PostAuthorCreationDate,
    COALESCE(u2.LastAccessDate, u.LastAccessDate) AS PostAuthorLastAccessDate
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Users u2 ON p.LastEditorUserId = u2.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Badges b ON u.Id = b.UserId
ORDER BY p.CreationDate DESC
LIMIT 100;
