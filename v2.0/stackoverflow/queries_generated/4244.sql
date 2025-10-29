-- {"query": "4244.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1394} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        AVG(p.Score) AS AveragePostScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= DATE('now', '-1 year') -- Consider users created in the last year
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostType,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE
            WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2)
            ELSE 0
        END AS AnswerCountForQuestion,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankByType,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= DATE('now', '-6 months') -- Consider posts created in the last 6 months
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        COUNT(p.Id) AS TotalQuestionsWithTag,
        AVG(p.Score) AS AverageScoreForTagQuestions
    FROM Tags t
    LEFT JOIN Posts p ON t.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
    WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-1 year')
    GROUP BY t.TagName, t.Count
    HAVING COUNT(p.Id) > 100 -- Only consider popular tags
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeCount,
    ua.UpVoteCount,
    ua.DownVoteCount,
    ua.AveragePostScore,
    ua.ClosedPostCount,
    pe.PostId,
    pe.Title,
    pe.PostType,
    pe.PostCreationDate,
    pe.Score,
    pe.ViewCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.AnswerCountForQuestion,
    pe.CommentCountOnPost,
    pe.ScoreRankByType,
    pe.PreviousPostScore,
    tp.TagName,
    tp.TagPostCount,
    tp.TotalQuestionsWithTag,
    tp.AverageScoreForTagQuestions,
    CASE
        WHEN ua.Reputation > 10000 AND pe.Score > 50 THEN 'High_Rep_High_Score_Post'
        WHEN ua.UserCreationDate < DATE('now', '-3 years') AND pe.ViewCount > 5000 THEN 'Old_User_Popular_Post'
        WHEN pe.AnswerCountForQuestion = 0 AND pe.CommentCountOnPost > 5 THEN 'Unanswered_Engaged_Post'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    COALESCE(ua.DisplayName, 'Anonymous') AS DisplayNameOrAnonymous,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pe.PostId AND pl.LinkTypeId = 1) AS OutgoingLinks,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = pe.PostId AND pl.LinkTypeId = 3) AS DuplicateOfCount,
    CASE
        WHEN ua.LastPostActivityDate IS NULL THEN 'No_Activity'
        WHEN ua.LastPostActivityDate >= DATE('now', '-30 days') THEN 'Active_Last_30_Days'
        ELSE 'Inactive'
    END AS UserActivityStatus,
    ua.ReputationRank
FROM UserActivity ua
FULL OUTER JOIN PostEngagement pe ON ua.UserId = pe.OwnerUserId
LEFT JOIN TagPopularity tp ON tp.TagName = ANY(SELECT TagName FROM TagPopularity WHERE TagName = ANY(STRING_TO_ARRAY(SUBSTRING(pe.Title, 2, LENGTH(pe.Title) - 2), '><')))
WHERE ua.UserId IS NOT NULL OR pe.PostId IS NOT NULL -- Ensure we don't get completely empty rows from FULL OUTER JOIN if one side is empty
ORDER BY ua.Reputation DESC, pe.Score DESC, tp.TagPostCount DESC;
