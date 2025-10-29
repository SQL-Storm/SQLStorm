-- {"query": "2793.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1412} 
WITH QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        ARRAY_REMOVE(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), '') AS TagArray
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
AnswerWithVotes AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        a.CreationDate AS AnswerCreationDate,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByScore
    FROM Posts a
    LEFT JOIN Votes v ON a.Id = v.PostId
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.Score, a.CreationDate, u.Id, u.DisplayName
),
TopAnswers AS (
    SELECT *
    FROM AnswerWithVotes
    WHERE RankByScore = 1
),
QuestionWithTopAnswer AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.OwnerUserId,
        q.OwnerDisplayName,
        q.Reputation AS OwnerReputation,
        q.TagArray,
        ta.AnswerId,
        ta.AnswerScore,
        ta.UpVotes,
        ta.DownVotes,
        ta.AnswerCreationDate,
        ta.OwnerUserId AS AnswerOwnerUserId,
        ta.OwnerDisplayName AS AnswerOwnerDisplayName
    FROM QuestionStats q
    LEFT JOIN TopAnswers ta ON q.QuestionId = ta.QuestionId
),
BadgesAgg AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        COUNT(DISTINCT Name) AS DistinctBadges
    FROM Badges
    GROUP BY UserId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        LEAD(u.LastAccessDate) OVER (ORDER BY u.Reputation DESC) AS NextUserLastAccessDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.LastAccessDate
)
SELECT
    q.QuestionId,
    q.Title,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.OwnerReputation,
    COALESCE(b.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(b.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(b.BronzeBadges, 0) AS OwnerBronzeBadges,
    COALESCE(b.DistinctBadges, 0) AS OwnerDistinctBadges,
    q.AnswerId,
    q.AnswerScore,
    q.UpVotes,
    q.DownVotes,
    q.AnswerCreationDate,
    q.AnswerOwnerUserId,
    q.AnswerOwnerDisplayName,
    ua.PostsCount AS AnswerOwnerPostsCount,
    ua.CommentsCount AS AnswerOwnerCommentsCount,
    ua.LastPostDate AS AnswerOwnerLastPostDate,
    ua.LastCommentDate AS AnswerOwnerLastCommentDate,
    ua.NextUserLastAccessDate,
    -- Calculate tag popularity: average number of questions per tag with more than 1000 questions
    (
        SELECT AVG(t.Cnt)
        FROM (
            SELECT unnest(q.TagArray) AS tg
        ) AS tags
        JOIN Tags t ON tags.tg = t.TagName
        WHERE t.Count > 1000
    ) AS AvgPopularTagCount,
    -- Latest close reason if closed (complex correlated subquery with null handling)
    (
        SELECT cht.Name
        FROM PostHistory ph
        JOIN PostHistoryTypes cht ON ph.PostHistoryTypeId = cht.Id
        LEFT JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
        WHERE ph.PostId = q.QuestionId AND ph.PostHistoryTypeId = 10
        ORDER BY ph.CreationDate DESC
        LIMIT 1
    ) AS LatestCloseReason,
    -- Complex string expression: concatenated first 3 tags separated by ' | '
    (
        SELECT STRING_AGG(tg, ' | ' ORDER BY tg)
        FROM (
            SELECT unnest(q.TagArray) AS tg
            LIMIT 3
        ) AS LimitedTags
    ) AS Top3TagsConcatenated,
    -- Window function over questions to rank by score and view count ratio
    RANK() OVER (ORDER BY NULLIF(q.Score,0)::float / NULLIF(q.ViewCount,0) DESC NULLS LAST) AS ScoreViewRatioRank
FROM QuestionWithTopAnswer q
LEFT JOIN BadgesAgg b ON q.OwnerUserId = b.UserId
LEFT JOIN UserActivity ua ON q.AnswerOwnerUserId = ua.UserId
WHERE q.QuestionCreationDate > '2018-01-01'
  AND (q.AnswerScore IS NULL OR q.AnswerScore >= 0)
HAVING COALESCE(q.AnswerScore, 0) + q.QuestionScore > 10
ORDER BY ScoreViewRatioRank
LIMIT 100;