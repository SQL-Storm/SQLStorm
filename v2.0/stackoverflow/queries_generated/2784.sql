-- {"query": "2784.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2127} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ARRAY[t.TagName] AS PathTags,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        rth.PathTags || child.TagName,
        rth.Level + 1
    FROM Tags child
    JOIN PostLinks pl ON pl.PostId = child.ExcerptPostId
    JOIN RecursiveTagHierarchy rth ON pl.RelatedPostId = rth.ExcerptPostId
    WHERE rth.Level < 3
),

SummarizedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Title, '') AS Title,
        COALESCE(p.Tags, '') AS Tags,
        p.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) OVER (PARTITION BY p.Id) AS LastEditDate
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),

BadgeCounts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
),

UserActivityRanked AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(bc.GoldBadges, 0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(bc.TotalBadges, 0) AS TotalBadges,
        COALESCE(pCounts.PostCount, 0) AS PostCount,
        RANK() OVER (ORDER BY COALESCE(pCounts.PostCount, 0) DESC, u.Reputation DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN BadgeCounts bc ON u.Id = bc.UserId
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount
        FROM Posts
        GROUP BY OwnerUserId
    ) pCounts ON u.Id = pCounts.OwnerUserId
    WHERE u.Reputation > 1000
),

TopQuestions AS (
    SELECT
        sp.*,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.TotalBadges,
        us.ActivityRank,
        ROW_NUMBER() OVER (
            PARTITION BY sp.OwnerUserId
            ORDER BY sp.Score DESC, sp.ViewCount DESC
        ) AS ScoreRank
    FROM SummarizedPosts sp
    JOIN UserActivityRanked us ON sp.OwnerUserId = us.Id
    WHERE sp.PostTypeId = 1 AND sp.Score > 10
),

AnswerAgg AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.CreationDate) AS FirstAnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),

FinalPosts AS (
    SELECT
        tq.Id AS QuestionId,
        tq.Title,
        tq.Tags,
        tq.Score AS QuestionScore,
        tq.ViewCount,
        tq.AcceptedAnswerId,
        tq.OwnerUserId,
        tq.OwnerName,
        tq.Reputation,
        tq.GoldBadges,
        tq.SilverBadges,
        tq.BronzeBadges,
        tq.TotalBadges,
        tq.ActivityRank,
        tq.CommentCount,
        COALESCE(aa.AnswerCount, 0) AS AnswerCount,
        COALESCE(aa.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(aa.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(aa.FirstAnswerDate, tq.CreationDate) AS FirstAnswerDate,
        ROW_NUMBER() OVER (PARTITION BY tq.OwnerUserId ORDER BY tq.Score DESC) AS UserTopQuestionRank
    FROM TopQuestions tq
    LEFT JOIN AnswerAgg aa ON aa.QuestionId = tq.Id
),

DuplicatesCTE AS (
    SELECT
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId,
        p1.Score AS DuplicateScore,
        p2.Score AS OriginalScore,
        pl.CreationDate AS LinkDate
    FROM PostLinks pl
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE pl.LinkTypeId = 3 -- Duplicate
      AND p1.PostTypeId = 1
      AND p2.PostTypeId = 1
),

CombinedResults AS (
    SELECT
        fp.QuestionId,
        fp.Title,
        fp.Tags,
        fp.QuestionScore,
        fp.ViewCount,
        fp.AcceptedAnswerId,
        fp.OwnerUserId,
        fp.OwnerName,
        fp.Reputation,
        fp.GoldBadges,
        fp.SilverBadges,
        fp.BronzeBadges,
        fp.TotalBadges,
        fp.ActivityRank,
        fp.CommentCount,
        fp.AnswerCount,
        fp.AvgAnswerScore,
        fp.MaxAnswerScore,
        fp.FirstAnswerDate,
        d.DuplicateQuestionId,
        d.OriginalQuestionId,
        d.DuplicateScore,
        d.OriginalScore,
        d.LinkDate
    FROM FinalPosts fp
    LEFT JOIN DuplicatesCTE d ON fp.QuestionId = d.DuplicateQuestionId
)

SELECT
    cr.QuestionId,
    cr.Title,
    cr.Tags,
    LENGTH(cr.Title) AS TitleLength,
    cr.QuestionScore,
    cr.ViewCount,
    CONCAT('User: ', COALESCE(cr.OwnerName, 'Unknown'), ' (Rep: ', cr.Reputation, ')') AS OwnerInfo,
    CASE
        WHEN cr.GoldBadges + cr.SilverBadges + cr.BronzeBadges > 10 THEN 'Veteran'
        WHEN cr.GoldBadges + cr.SilverBadges + cr.BronzeBadges BETWEEN 5 AND 10 THEN 'Experienced'
        ELSE 'Newbie'
    END AS UserCategory,
    cr.CommentCount,
    cr.AnswerCount,
    ROUND(cr.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    cr.MaxAnswerScore,
    cr.FirstAnswerDate,
    cr.DuplicateQuestionId,
    cr.OriginalQuestionId,
    CONCAT('DupScore:', cr.DuplicateScore, '|OrigScore:', cr.OriginalScore) AS DuplicateScoreInfo,
    cr.LinkDate,
    COALESCE(rth.PathTags[array_upper(rth.PathTags,1)], 'No Hierarchy') AS DeepestTagInHierarchy,
    COUNT(DISTINCT vp.Id) FILTER (WHERE vp.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT vp.Id) FILTER (WHERE vp.VoteTypeId = 3) AS DownVotes,
    COALESCE(phClose.Name, 'Not Closed') AS LatestCloseReason,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
    FIRST_VALUE(us.DisplayName) OVER (PARTITION BY cr.OwnerUserId ORDER BY us.LastAccessDate DESC) AS MostRecentActiveUser
FROM CombinedResults cr
LEFT JOIN RecursiveTagHierarchy rth ON rth.TagName = ANY(string_to_array(substring(cr.Tags FROM 2 FOR length(cr.Tags)-2), '><'))
LEFT JOIN Votes vp ON vp.PostId = cr.QuestionId
LEFT JOIN PostHistory ph ON ph.PostId = cr.QuestionId AND ph.PostHistoryTypeId = 10
LEFT JOIN CloseReasonTypes phClose ON ph.Comment::int = phClose.Id
LEFT JOIN Users us ON us.Id = cr.OwnerUserId
WHERE cr.ActivityRank <= 100
  AND (cr.QuestionScore > 15 OR cr.AnswerCount > 5)
GROUP BY
    cr.QuestionId,
    cr.Title,
    cr.Tags,
    cr.QuestionScore,
    cr.ViewCount,
    cr.OwnerName,
    cr.Reputation,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.TotalBadges,
    cr.ActivityRank,
    cr.CommentCount,
    cr.AnswerCount,
    cr.AvgAnswerScore,
    cr.MaxAnswerScore,
    cr.FirstAnswerDate,
    cr.DuplicateQuestionId,
    cr.OriginalQuestionId,
    cr.DuplicateScore,
    cr.OriginalScore,
    cr.LinkDate,
    rth.PathTags,
    phClose.Name,
    ph.Id,
    us.DisplayName,
    us.LastAccessDate
ORDER BY
    cr.QuestionScore DESC,
    cr.AnswerCount DESC,
    cr.ViewCount DESC
LIMIT 50;
