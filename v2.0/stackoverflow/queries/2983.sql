-- {"query": "2983.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1312}
WITH RecursivePostTags AS (
    SELECT 
        p.Id AS PostId,
        TRIM(tag) AS Tag
    FROM 
        Posts p
        JOIN LATERAL (
            SELECT regexp_split as tag
            FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><')) AS t(regexp_split)
        ) t ON TRUE
    WHERE 
        p.PostTypeId = 1
), HighRepUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(COALESCE(p.Score,0)) AS TotalPostScore,
        AVG(COALESCE(p.Score,0)) AS AvgPostScore,
        COUNT(p.Id) AS PostCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE
        u.Reputation > 10000
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
), LatestPostHistory AS (
    SELECT
        ph.PostId,
        ph.Id AS HistoryId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment
    FROM (
        SELECT
            ph.*,
            ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10,11,12,13,14,15)
    ) ph
    WHERE ph.rn = 1
), VotesSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteVotes,
        COUNT(CASE WHEN v.VoteTypeId = 6 THEN 1 END) AS CloseVotes,
        COUNT(v.Id) AS TotalVotes
    FROM
        Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY
        p.Id
), RankedAnswers AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByScore,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate ASC) AS RankByDate
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
), UserCommentSentiment AS (
    SELECT
        c.UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(LENGTH(c.Text) - LENGTH(REPLACE(c.Text, '!', ''))) AS ExclamationCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN LOWER(c.Text) ~ '(\\berror\\b|\\bfail\\b|\\bbug\\b|\\bissue\\b|\\bproblem\\b)' THEN 1 ELSE 0 END) AS NegativeMentions
    FROM
        Comments c
        LEFT JOIN Users u ON u.Id = c.UserId
    GROUP BY
        c.UserId, u.DisplayName
)
SELECT
    hp.Id AS PostId,
    hp.Title,
    hp.OwnerUserId,
    COALESCE(hu.DisplayName, hp.OwnerDisplayName) AS OwnerName,
    hp.CreationDate,
    hp.Score,
    hp.ViewCount,
    COALESCE(vs.UpVotes,0) AS UpVotes,
    COALESCE(vs.DownVotes,0) AS DownVotes,
    COALESCE(vs.FavoriteVotes,0) AS FavoriteVotes,
    COALESCE(vs.CloseVotes,0) AS CloseVotes,
    COALESCE(rans.RankByScore, NULL) AS AnswerScoreRank,
    COALESCE(rans.RankByDate, NULL) AS AnswerDateRank,
    COALESCE(rph.PostHistoryTypeId, NULL) AS LatestPostHistoryType,
    COALESCE(rph.Comment, NULL) AS LatestPostHistoryComment,
    COALESCE(ht.Tag, 'NoTag') AS Tag,
    COALESCE(ucs.CommentCount, 0) AS UserCommentCount,
    COALESCE(ucs.ExclamationCount, 0) AS ExclamationCountInComments,
    COALESCE(ucs.NegativeMentions, 0) AS NegativeSentimentComments,
    CASE
        WHEN hu.Reputation IS NULL THEN 'LowRepUser'
        WHEN hu.Reputation > 50000 THEN 'HighRepUser'
        ELSE 'MidRepUser'
    END AS UserReputationCategory,
    ('Score:' || hp.Score || ';View:' || hp.ViewCount || ';TagsCount:' || (CHAR_LENGTH(hp.Tags) - CHAR_LENGTH(REPLACE(hp.Tags,'><','')) + 1)) AS ScoreViewTagsSummary
FROM
    Posts hp
    LEFT JOIN HighRepUsers hu ON hu.Id = hp.OwnerUserId
    LEFT JOIN VotesSummary vs ON vs.PostId = hp.Id
    LEFT JOIN RankedAnswers rans ON rans.Id = hp.Id
    LEFT JOIN LatestPostHistory rph ON rph.PostId = hp.Id
    LEFT JOIN RecursivePostTags ht ON ht.PostId = hp.Id
    LEFT JOIN UserCommentSentiment ucs ON ucs.UserId = hp.OwnerUserId
WHERE 
    hp.PostTypeId = 1
    AND (
        hp.Score > (SELECT AVG(Score)*1.5 FROM Posts WHERE PostTypeId=1)
        OR hp.ViewCount > (SELECT AVG(ViewCount)*1.5 FROM Posts WHERE PostTypeId=1)
        OR hp.AnswerCount > 5
    )
    AND EXISTS (
        SELECT 1 
        FROM PostHistory phc 
        WHERE phc.PostId = hp.Id 
          AND phc.PostHistoryTypeId IN (10, 11)
          AND phc.CreationDate > hp.CreationDate - INTERVAL '30' DAY
    )
ORDER BY 
    hp.Score DESC, hp.ViewCount DESC, hp.CreationDate DESC
LIMIT 100;