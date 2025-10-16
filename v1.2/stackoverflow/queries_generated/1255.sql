-- {"query": "1255.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1814} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        NULL::int AS ParentTagId
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        rh.Level + 1,
        rh.Id AS ParentTagId
    FROM Tags child
    INNER JOIN RecursiveTagHierarchy rh ON char_length(child.TagName) > char_length(rh.TagName)
        AND substring(child.TagName, 1, char_length(rh.TagName)) = rh.TagName
        AND child.Id <> rh.Id
    WHERE rh.Level < 3
),
TopUserBadges AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - interval '1 year'
),
UserBadgeCount AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        COALESCE(SUM(v.Score),0) AS TotalVoteScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3) -- upvotes and downvotes
    GROUP BY u.Id, u.DisplayName
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.CreationDate AS AnswerCreation,
        a.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
FlaggedCloseReasons AS (
    SELECT ph.PostId, ph.Comment AS CloseReasonId, COUNT(*) AS CloseReasonCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY ph.PostId, ph.Comment
),
HighActivityQuestions AS (
    SELECT 
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.ViewCount,
        q.Score,
        q.AnswerCount,
        q.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentsCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id) AS VotesCount,
        EXISTS(SELECT 1 FROM PostLinks pl WHERE pl.PostId = q.Id) AS HasLinksToOtherPosts
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.ViewCount > 1000
      AND q.AnswerCount > 3
      AND q.ClosedDate IS NULL
),
UserAnswerScoreRankings AS (
    SELECT 
        a.AnswerOwnerId,
        a.AnswerId,
        a.AnswerScore,
        RANK() OVER (PARTITION BY a.AnswerOwnerId ORDER BY a.AnswerScore DESC) AS ScoreRank
    FROM QuestionAnswerStats a
    WHERE a.AnswerOwnerId IS NOT NULL
),
StringTagAgg AS (
    SELECT 
        QuestionId,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS SortedTags
    FROM (
        SELECT 
            p.Id AS QuestionId,
            unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags) - 2), '><')) AS TagName
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) AS tag_expanded
    INNER JOIN Tags t ON t.TagName = tag_expanded.TagName
    GROUP BY QuestionId
)
SELECT 
    q.Id AS QuestionId,
    q.Title,
    uc.DisplayName AS QuestionOwner,
    uc.Reputation AS OwnerReputation,
    q.ViewCount,
    q.Score AS QuestionScore,
    q.AnswerCount,
    qa.AnswerId,
    ua.DisplayName AS TopAnswerer,
    qa.AnswerScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    us.ScoreRank,
    fcr.CloseReasonId,
    fcr.CloseReasonCount,
    hq.CommentsCount,
    hq.VotesCount,
    hq.HasLinksToOtherPosts,
    st.SortedTags,
    rh.Level AS TagHierarchyLevel,
    rh.ParentTagId,
    rh.TagName AS HierarchicalTagName,
    rh.Count AS TagUseCount,
    CASE 
        WHEN ua.ProfileImageUrl IS NULL THEN 'https://stackoverflow.com/default-profile.png' 
        ELSE ua.ProfileImageUrl 
    END AS AnswererProfileImage,
    CASE 
        WHEN q.ClosedDate IS NULL THEN 'Open'
        ELSE 'Closed'
    END AS QuestionStatus,
    CONCAT(
        COALESCE(uc.Location, 'Unknown'), ' | ', 
        COALESCE(LEFT(ua.Location, 20), 'N/A'), ' | ',
        EXTRACT(year FROM age(current_timestamp, ua.CreationDate))::TEXT,
        ' years on SE'
    ) AS LocationAndTenureSummary,
    REGEXP_REPLACE(
        COALESCE(qa.AnswerId::TEXT, 'NoAnswer'),
        '(\d{3})',
        '\1-',
        'g'
    ) AS FormattedAnswerId,
    -- Correlated subquery for latest edit date
    (SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS LatestSignificantEdit,
    -- Windowed average of question scores per owner
    AVG(q.Score) OVER (PARTITION BY q.OwnerUserId) AS AvgOwnerQuestionScore
FROM Posts q
INNER JOIN Users uc ON q.OwnerUserId = uc.Id
LEFT JOIN QuestionAnswerStats qa ON qa.QuestionId = q.Id AND qa.AnswerRank = 1
LEFT JOIN Users ua ON qa.AnswerOwnerId = ua.Id
LEFT JOIN UserBadgeCount ub ON ua.Id = ub.UserId
LEFT JOIN UserAnswerScoreRankings us ON qa.AnswerOwnerId = us.AnswerOwnerId AND qa.AnswerId = us.AnswerId
LEFT JOIN FlaggedCloseReasons fcr ON fcr.PostId = q.Id
LEFT JOIN HighActivityQuestions hq ON hq.Id = q.Id
LEFT JOIN StringTagAgg st ON st.QuestionId = q.Id
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY (string_to_array(substring(q.Tags, 2, char_length(q.Tags) - 2), '><'))
WHERE q.PostTypeId = 1
  AND q.CreationDate > CURRENT_DATE - INTERVAL '2 year'
  AND (qa.AnswerScore IS NULL OR qa.AnswerScore > 0)
  AND (
       (ub.TotalBadges > 10 OR ub.TotalBadges IS NULL)  -- accept users that have no badges as well
       OR q.ViewCount > 5000
      )
ORDER BY q.Score DESC NULLS LAST, ub.TotalBadges DESC NULLS LAST, q.ViewCount DESC NULLS LAST, qa.AnswerScore DESC NULLS LAST
LIMIT 50
UNION ALL
SELECT 
    NULL, 'Footer summary row with aggregations', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    CURRENT_TIMESTAMP, NULL, NULL
ORDER BY 1 NULLS LAST;
