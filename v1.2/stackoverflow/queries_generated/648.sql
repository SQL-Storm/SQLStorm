-- {"query": "648.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1815} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE NOT EXISTS (
        SELECT 1 FROM PostLinks pl 
        JOIN Posts p ON pl.PostId = p.Id
        WHERE pl.RelatedPostId = t.ExcerptPostId AND pl.LinkTypeId = 1
    )
    UNION ALL
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN PostLinks pl ON pl.RelatedPostId = t.ExcerptPostId AND pl.LinkTypeId = 1
    JOIN RecursiveTagHierarchy r ON pl.PostId = r.ExcerptPostId
    WHERE t.Id <> ALL(r.TagPath)
),
UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadges,
        COALESCE(MAX(b.Date), u.CreationDate) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
        q.Tags,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS RecentQuestionRank
    FROM Posts q
    LEFT JOIN (
        SELECT 
            ParentId,
            COUNT(*) AS AnswerCount,
            MAX(Score) AS MaxAnswerScore,
            AVG(Score) AS AvgAnswerScore
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1
),
UserActivityWindow AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        COUNT(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate 
            ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS PostsLast30Days,
        COUNT(*) OVER (PARTITION BY u.Id ORDER BY p.CreationDate 
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW) AS PostsLastYear
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
TopQuestionsWithComments AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.MaxAnswerScore,
        q.AvgAnswerScore,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters,
        STRING_AGG(DISTINCT COALESCE(ph.Comment, '')) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseReasons
    FROM QuestionAnswerStats q
    LEFT JOIN Comments c ON c.PostId = q.QuestionId
    LEFT JOIN PostHistory ph ON ph.PostId = q.QuestionId AND ph.PostHistoryTypeId = 10
    WHERE q.Score > 10
    GROUP BY q.QuestionId, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.MaxAnswerScore, q.AvgAnswerScore
),
DuplicateQuestions AS (
    SELECT DISTINCT 
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId,
        p1.Title AS DuplicateTitle,
        p2.Title AS OriginalTitle,
        pl.CreationDate AS LinkDate
    FROM PostLinks pl
    JOIN Posts p1 ON p1.Id = pl.PostId AND p1.PostTypeId = 1
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId AND p2.PostTypeId = 1
    WHERE pl.LinkTypeId = 3
),
UserVoteSummary AS (
    SELECT 
        v.UserId,
        v.VoteTypeId,
        COUNT(*) AS VoteCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyAmount
    FROM Votes v
    GROUP BY v.UserId, v.VoteTypeId
),
ComplexUserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.UniqueBadges,
        COALESCE(uvs_up.VoteCount, 0) AS UpVotesGiven,
        COALESCE(uvs_down.VoteCount, 0) AS DownVotesGiven,
        COALESCE(uvs_bounty.TotalBountyAmount, 0) AS BountySpent,
        ua.PostsLast30Days,
        ua.PostsLastYear
    FROM Users u
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    LEFT JOIN UserVoteSummary uvs_up ON uvs_up.UserId = u.Id AND uvs_up.VoteTypeId = 2
    LEFT JOIN UserVoteSummary uvs_down ON uvs_down.UserId = u.Id AND uvs_down.VoteTypeId = 3
    LEFT JOIN UserVoteSummary uvs_bounty ON uvs_bounty.UserId = u.Id AND uvs_bounty.VoteTypeId IN (8,9)
    LEFT JOIN (
        SELECT UserId, MAX(PostsLast30Days) AS PostsLast30Days, MAX(PostsLastYear) AS PostsLastYear
        FROM UserActivityWindow
        GROUP BY UserId
    ) ua ON ua.UserId = u.Id
),
FinalOutput AS (
    SELECT 
        q.Title AS QuestionTitle,
        q.ViewCount,
        q.Score,
        q.AnswerCount,
        q.MaxAnswerScore,
        q.AvgAnswerScore,
        q.CommentCount,
        q.Commenters,
        q.CloseReasons,
        d.DuplicateTitle,
        u.DisplayName AS QuestionOwner,
        u.Reputation AS OwnerReputation,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.UniqueBadges,
        u.UpVotesGiven,
        u.DownVotesGiven,
        u.BountySpent,
        u.PostsLast30Days,
        u.PostsLastYear,
        t.TagName,
        t.Count AS TagCount,
        CASE 
            WHEN q.Score > 50 AND q.AnswerCount > 5 THEN 'High Engagement'
            WHEN q.Score BETWEEN 10 AND 50 THEN 'Moderate Engagement'
            ELSE 'Low Engagement'
        END AS EngagementLevel,
        COALESCE(NULLIF(q.Title, ''), 'No Title') || ' [' || COALESCE(t.TagName, 'No Tag') || ']' AS TitleWithTag,
        LENGTH(q.Title) AS TitleLength,
        POSITION('?' IN q.Title) > 0 AS IsQuestion,
        (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = q.QuestionId AND c2.CreationDate > q.CreationDate) AS CommentsAfterQuestion,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY q.Score DESC) AS UserTopQuestionRank
    FROM TopQuestionsWithComments q
    LEFT JOIN DuplicateQuestions d ON d.DuplicateQuestionId = q.QuestionId
    LEFT JOIN ComplexUserStats u ON u.Id = q.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(coalesce(q.Title, ''), ' ')) AS TagName
        ORDER BY TagName
        LIMIT 1
    ) t ON TRUE
)
SELECT *
FROM FinalOutput
WHERE EngagementLevel IN ('High Engagement', 'Moderate Engagement')
ORDER BY Score DESC, ViewCount DESC
LIMIT 100;
