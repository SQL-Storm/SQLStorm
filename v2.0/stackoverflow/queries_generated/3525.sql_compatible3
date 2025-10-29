WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.CreationDate, TIMESTAMP '1970-01-01') AS UserCreated,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVoteGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVoteGiven,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
),
QuestionMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.FavoriteCount,
        q.Tags,
        COALESCE(q.AcceptedAnswerId, 0) AS HasAccepted,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY q.Tags ORDER BY q.ViewCount DESC) AS TagRank
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= DATE '2023-01-01'
),
-- normalize tag splitting in a dialect-agnostic way: split into rows by replacing leading/trailing <> and splitting on '><'
TagSplit AS (
    SELECT
        qm.QuestionId,
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM substring_tag)) AS tag
    FROM QuestionMetrics qm,
    LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM qm.Tags)), '><')) AS substring_tag
    ) s
    WHERE qm.Tags IS NOT NULL AND qm.Tags <> ''
),
TagPopularity AS (
    SELECT
        tag AS Tag,
        COUNT(*) AS TagUseCount
    FROM TagSplit
    GROUP BY tag
),
TopTags AS (
    SELECT Tag
    FROM TagPopularity
    WHERE TagUseCount >= 100
    ORDER BY TagUseCount DESC
    LIMIT 10
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.BadgeCount,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVoteGiven,
    us.DownVoteGiven,
    us.LastPostDate,
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.FavoriteCount,
    q.AnswerCount AS Q_AnswerCount,
    q.UpVotes,
    q.DownVotes,
    CASE
        WHEN q.HasAccepted <> 0 THEN 'Accepted'
        WHEN q.AnswerCount = 0 THEN 'NoAnswers'
        ELSE 'Pending'
    END AS AnswerStatus,
    COALESCE(NULLIF(q.Tags, ''), '<none>') AS TagString,
    ARRAY_AGG(DISTINCT tt.Tag) FILTER (WHERE tt.Tag IS NOT NULL) AS TopTagList
FROM UserStats us
LEFT JOIN Posts p
       ON p.OwnerUserId = us.Id AND p.PostTypeId = 1
LEFT JOIN QuestionMetrics q
       ON q.QuestionId = p.Id
      AND (q.Tags IS NOT NULL AND q.Tags <> '')
-- join to TopTags via tag-split lateral to avoid non-inner join on subquery
LEFT JOIN LATERAL (
    SELECT tt.Tag
    FROM TopTags tt
    JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM COALESCE(q.Tags, ''))), '><')) AS ttag
    ) t ON tt.Tag = t.ttag
) tt ON TRUE
WHERE (us.Reputation > 10000 OR us.BadgeCount >= 5)
  AND (q.AnswerCount IS NULL OR q.AnswerCount > 0)
GROUP BY
    us.Id, us.DisplayName, us.Reputation, us.BadgeCount,
    us.QuestionCount, us.AnswerCount, us.UpVoteGiven, us.DownVoteGiven,
    us.LastPostDate,
    q.QuestionId, q.Title, q.CreationDate, q.Score, q.ViewCount,
    q.FavoriteCount, q.AnswerCount, q.UpVotes, q.DownVotes, q.HasAccepted, q.Tags

UNION ALL

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.BadgeCount,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVoteGiven,
    us.DownVoteGiven,
    us.LastPostDate,
    CAST(NULL AS BIGINT) AS QuestionId,
    CAST(NULL AS TEXT) AS Title,
    CAST(NULL AS TIMESTAMP) AS CreationDate,
    CAST(NULL AS INTEGER) AS Score,
    CAST(NULL AS INTEGER) AS ViewCount,
    CAST(NULL AS INTEGER) AS FavoriteCount,
    CAST(NULL AS INTEGER) AS Q_AnswerCount,
    CAST(NULL AS INTEGER) AS UpVotes,
    CAST(NULL AS INTEGER) AS DownVotes,
    'NoQuestion' AS AnswerStatus,
    COALESCE(NULLIF(p.Tags, ''), '<none>') AS TagString,
    CAST(ARRAY[] AS TEXT[]) AS TopTagList
FROM UserStats us
LEFT JOIN Posts p
       ON p.OwnerUserId = us.Id AND p.PostTypeId = 1
WHERE NOT EXISTS (
        SELECT 1 FROM QuestionMetrics qm WHERE qm.QuestionId = p.Id
      )
  AND us.Reputation BETWEEN 5000 AND 10000
ORDER BY Reputation DESC, BadgeCount DESC, QuestionId NULLS LAST;