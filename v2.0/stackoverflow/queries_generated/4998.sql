-- {"query": "4998.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1100} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.UserDisplayName,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS TotalCommentsMade
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 -- Questions
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 2 -- Upvotes received by user
    LEFT JOIN Comments c ON u.Id = c.UserId -- Comments made by user
    GROUP BY u.Id, u.DisplayName
),
TagContribution AS (
    SELECT
        p.OwnerUserId,
        t.TagName,
        COUNT(*) AS PostCount
    FROM Posts p
    JOIN Tags t ON CAST(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS VARCHAR) = t.TagName -- Simplified tag extraction for demonstration
    WHERE p.PostTypeId = 1 -- Questions only
    GROUP BY p.OwnerUserId, t.TagName
),
TopTagContributors AS (
    SELECT
        tc.OwnerUserId,
        tc.TagName,
        tc.PostCount,
        ROW_NUMBER() OVER(PARTITION BY tc.OwnerUserId ORDER BY tc.PostCount DESC) as rnk
    FROM TagContribution tc
)
SELECT
    u.UserName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalUpvotesReceived,
    u.TotalCommentsMade,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
    CASE WHEN tc.TagName IS NOT NULL THEN tc.TagName ELSE 'No Primary Tag' END AS PrimaryTag,
    p.Title AS MostRecentEditedQuestionTitle,
    p.CreationDate AS MostRecentEditedQuestionDate,
    NULLIF(u.DisplayName, LOWER(u.DisplayName)) AS CaseSensitiveDisplayNameCheck,
    CASE
        WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External Website'
    END AS WebsiteCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    COALESCE(MAX(p.LastActivityDate), u.CreationDate) AS LastUserOrPostActivity
FROM UserActivity u
LEFT JOIN RankedPostEdits rpe ON u.UserId = rpe.UserId
LEFT JOIN Posts p ON rpe.PostId = p.Id AND rpe.rn = 1 -- Join to the most recent edit for a user on a post
LEFT JOIN TopTagContributors tc ON u.UserId = tc.OwnerUserId AND tc.rnk = 1
WHERE u.Reputation > 1000
GROUP BY
    u.UserName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalUpvotesReceived,
    u.TotalCommentsMade,
    tc.TagName,
    p.Title,
    p.CreationDate,
    u.DisplayName,
    u.WebsiteUrl,
    u.CreationDate
HAVING COUNT(DISTINCT rpe.PostId) > 0 -- Only users who have edited at least one post
ORDER BY u.Reputation DESC, u.AnswerCount DESC;