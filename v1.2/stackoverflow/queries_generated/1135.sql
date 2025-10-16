-- {"query": "1135.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1562} 

WITH RecursiveTagPaths AS (
    SELECT 
        t.Id,
        CAST(t.TagName AS VARCHAR(500)) AS Path,
        CAST(t.TagName AS VARCHAR(35)) AS LastTag
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        CONCAT(rtp.Path, ' > ', t2.TagName),
        t2.TagName
    FROM Tags t2
    JOIN RecursiveTagPaths rtp ON t2.Id <> rtp.Id
    WHERE t2.IsModeratorOnly = 0 AND t2.IsRequired = 0
    AND CHAR_LENGTH(rtp.Path) < 100
),
UserQuestionStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COALESCE(SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END), 0) AS TotalPositiveScore,
        AVG(COALESCE(p.Score,0)) OVER (PARTITION BY u.Id) AS AvgPostScore,
        ROW_NUMBER() OVER (
            PARTITION BY u.Location
            ORDER BY COALESCE(SUM(COALESCE(p.Score,0)),0) DESC
        ) AS RankByLocation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000 AND u.CreationDate < NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Location
),
PostWithCommentsRanking AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        c.CommentCount,
        RANK() OVER (
            ORDER BY p.Score DESC, c.CommentCount DESC, p.ViewCount DESC
        ) AS PopularityRank
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
FilteredHistory AS (
    SELECT ph.*,
        cht.Name AS HistoryTypeName,
        crt.Name AS CloseReasonName
    FROM PostHistory ph
    LEFT JOIN PostHistoryTypes cht ON cht.Id = ph.PostHistoryTypeId
    LEFT JOIN CloseReasonTypes crt ON crt.Id::varchar = ph.Comment
    WHERE ph.CreationDate >= NOW() - INTERVAL '2 years'
),
RecentDuplicates AS (
    SELECT DISTINCT pl.PostId, pl.RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- Duplicate link type
      AND pl.CreationDate >= NOW() - INTERVAL '1 year'
),
QuestionAnswerDetails AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerCommentCount,
        -- correlated subquery to pull latest edit editor display name
        (
            SELECT ph.UserDisplayName 
            FROM PostHistory ph
            WHERE ph.PostId = a.Id AND ph.PostHistoryTypeId IN (4,5,6) -- Edits: title/body/tags
            ORDER BY ph.CreationDate DESC LIMIT 1
        ) AS LastEditorDisplayName
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        b.Name,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS MostRecentBadgeDate
    FROM Badges b
    GROUP BY b.UserId, b.Name
)
SELECT 
    uqs.UserId,
    uqs.DisplayName,
    uqs.QuestionsCount,
    uqs.AnswersCount,
    uqs.TotalPositiveScore,
    COALESCE(ubs.GoldBadges,0) AS GoldBadges,
    COALESCE(ubs.SilverBadges,0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges,0) AS BronzeBadges,
    pwcr.PopularityRank,
    CONCAT(
      CASE WHEN pwcr.Title IS NOT NULL THEN SUBSTRING(pwcr.Title, 1, 60) ELSE 'No Title' END,
      ' - Score: ', pwcr.Score,
      ' - Comments: ', COALESCE(pwcr.CommentCount,0),
      ' - Views: ', pwcr.ViewCount
    ) AS TopQuestionSummary,
    rtp.Path AS RandomTagPath,
    fhs.HistoryTypeName,
    fhs.CloseReasonName,
    fhs.CreationDate AS LastHistoryChange,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerCommentCount,
    COALESCE(qa.LastEditorDisplayName, 'Unknown') AS LastAnswerEditor,
    uqs.RankByLocation
FROM UserQuestionStats uqs
LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = uqs.UserId
LEFT JOIN PostWithCommentsRanking pwcr ON pwcr.PostId = (
    SELECT p2.Id FROM Posts p2
    WHERE p2.OwnerUserId = uqs.UserId AND p2.PostTypeId = 1 AND p2.ClosedDate IS NULL
    ORDER BY p2.Score DESC, p2.ViewCount DESC LIMIT 1
)
LEFT JOIN RecursiveTagPaths rtp ON rtp.LastTag = 
(
    SELECT SUBSTRING(
        COALESCE(t.Tags,''),
        '[^<>]+' -- simple approximation, database string manipulation functions may be required by actual dialect
        ) 
    FROM Posts t 
    WHERE t.OwnerUserId = uqs.UserId AND t.PostTypeId = 1
    LIMIT 1
)
LEFT JOIN FilteredHistory fhs ON fhs.UserId = uqs.UserId AND fhs.PostId = pwcr.PostId
LEFT JOIN QuestionAnswerDetails qa ON qa.QuestionId = pwcr.PostId AND qa.AnswerRank = 1
WHERE uqs.QuestionsCount > 10 
  AND (uqs.TotalPositiveScore > 100 OR (ubs.GoldBadges + ubs.SilverBadges + ubs.BronzeBadges) > 0)
  AND EXISTS (SELECT 1 FROM RecentDuplicates rd WHERE rd.PostId = pwcr.PostId OR rd.RelatedPostId = pwcr.PostId)
ORDER BY uqs.TotalPositiveScore DESC, uqs.QuestionsCount DESC, uqs.AnswersCount DESC
LIMIT 50;
