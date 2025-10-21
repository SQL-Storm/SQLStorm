-- {"query": "14021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 51370, "output_tokens": 23233} 
WITH cte AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.OwnerUserId, 
        p.Title, 
        p.Tags, 
        p.CreationDate,
        p.Score, 
        p.AnswerCount, 
        p.CommentCount,
        COALESCE(p.ClosedDate, '9999-12-31') AS ClosedDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(CAST(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS VARCHAR), '') AS TagList,
        COALESCE(DATEDIFF(DAY, p.CreationDate, COALESCE(p.ClosedDate, GETDATE())), 0) AS DaysSinceCreation,
        CASE 
            WHEN p.OwnerUserId IS NULL THEN -1
            ELSE p.OwnerUserId
        END AS OwnerUserId,
        COALESCE(u.Reputation, 0) AS Reputation,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        COALESCE(u.AboutMe, '') AS AboutMe,
        COALESCE(u.WebsiteUrl, '') AS WebsiteUrl,
        COALESCE(u.ProfileImageUrl, '') AS ProfileImageUrl
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
closed_questions AS (
    SELECT 
        Id, 
        Title, 
        Tags, 
        CreationDate, 
        ClosedDate, 
        DaysSinceCreation,
        OwnerUserId, 
        Reputation, 
        DisplayName, 
        Location, 
        AboutMe, 
        WebsiteUrl, 
        ProfileImageUrl
    FROM cte
    WHERE PostType = 'Question' AND ClosedDate < GETDATE()
),
top_answerers AS (
    SELECT 
        OwnerUserId, 
        COUNT(*) AS AnswerCount,
        SUM(Score) AS TotalScore
    FROM cte
    WHERE PostType = 'Answer'
    GROUP BY OwnerUserId
    ORDER BY TotalScore DESC
    FETCH FIRST 10 ROWS ONLY
),
active_users AS (
    SELECT 
        u.Id, 
        u.Reputation, 
        u.CreationDate, 
        u.DisplayName, 
        u.LastAccessDate, 
        u.WebsiteUrl, 
        u.Location, 
        u.AboutMe, 
        u.Views, 
        u.UpVotes, 
        u.DownVotes, 
        u.ProfileImageUrl, 
        u.EmailHash, 
        u.AccountId,
        DATEDIFF(DAY, u.LastAccessDate, GETDATE()) AS DaysSinceLastAccess
    FROM Users u
    WHERE u.LastAccessDate > DATEADD(MONTH, -3, GETDATE())
),
badge_summary AS (
    SELECT 
        b.UserId, 
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    cq.Id AS QuestionId,
    cq.Title AS QuestionTitle,
    cq.Tags AS QuestionTags,
    cq.CreationDate AS QuestionCreationDate,
    cq.ClosedDate AS QuestionClosedDate,
    cq.DaysSinceCreation AS DaysSinceQuestionCreation,
    cq.OwnerUserId AS QuestionOwnerUserId,
    cq.Reputation AS QuestionOwnerReputation,
    cq.DisplayName AS QuestionOwnerDisplayName,
    cq.Location AS QuestionOwnerLocation,
    cq.AboutMe AS QuestionOwnerAboutMe,
    cq.WebsiteUrl AS QuestionOwnerWebsiteUrl,
    cq.ProfileImageUrl AS QuestionOwnerProfileImageUrl,
    COALESCE(ta.AnswerCount, 0) AS AnswerCount,
    COALESCE(ta.TotalScore, 0) AS TotalAnswerScore,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    au.Id AS UserId,
    au.Reputation AS UserReputation,
    au.CreationDate AS UserCreationDate,
    au.DisplayName AS UserDisplayName,
    au.LastAccessDate AS UserLastAccessDate,
    au.WebsiteUrl AS UserWebsiteUrl,
    au.Location AS UserLocation,
    au.AboutMe AS UserAboutMe,
    au.Views AS UserViews,
    au.UpVotes AS UserUpVotes,
    au.DownVotes AS UserDownVotes,
    au.ProfileImageUrl AS UserProfileImageUrl,
    au.EmailHash AS UserEmailHash,
    au.AccountId AS UserAccountId,
    au.DaysSinceLastAccess AS DaysSinceUserLastAccess
FROM closed_questions cq
LEFT JOIN top_answerers ta ON cq.OwnerUserId = ta.OwnerUserId
LEFT JOIN badge_summary bs ON cq.OwnerUserId = bs.UserId
LEFT JOIN active_users au ON cq.OwnerUserId = au.Id
ORDER BY cq.DaysSinceCreation DESC, ta.TotalScore DESC, bs.TotalBadges DESC, au.DaysSinceLastAccess DESC;