-- {"query": "4609.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1262} 
WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as rn
    FROM Posts a
    WHERE a.PostTypeId = 2 AND a.Score > 0
),
QuestionData AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount,
        q.Tags,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN q.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        UPPER(SUBSTRING(q.Title FROM 1 FOR 1)) || LOWER(SUBSTRING(q.Title FROM 2 FOR LENGTH(q.Title))) AS FormattedTitle
    FROM Posts q
    WHERE q.PostTypeId = 1
),
UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        u.UpVotes,
        u.DownVotes,
        CASE
            WHEN u.WebsiteUrl IS NULL THEN 'No Website'
            WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
            ELSE 'External Website'
        END AS WebsiteCategory,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
),
TopAnswers AS (
    SELECT
        ra.AnswerId,
        ra.QuestionId,
        ra.OwnerUserId,
        ra.Score,
        ra.rn
    FROM RankedAnswers ra
    WHERE ra.rn <= 3
)
SELECT
    qd.QuestionId,
    qd.FormattedTitle,
    qd.QuestionCreationDate,
    qd.AnswerCount,
    qd.FavoriteCount,
    qd.ViewCount,
    qd.IsClosed,
    qd.IsCommunityOwned,
    COALESCE(urq.DisplayName, 'Community') AS QuestionOwnerDisplayName,
    COALESCE(urq.Reputation, 0) AS QuestionOwnerReputation,
    ta1.AnswerId AS TopAnswer1_Id,
    ta1.Score AS TopAnswer1_Score,
    COALESCE(urA1.DisplayName, 'Community') AS TopAnswer1_OwnerDisplayName,
    COALESCE(urA1.Reputation, 0) AS TopAnswer1_OwnerReputation,
    ta2.AnswerId AS TopAnswer2_Id,
    ta2.Score AS TopAnswer2_Score,
    COALESCE(urA2.DisplayName, 'Community') AS TopAnswer2_OwnerDisplayName,
    COALESCE(urA2.Reputation, 0) AS TopAnswer2_OwnerReputation,
    ta3.AnswerId AS TopAnswer3_Id,
    ta3.Score AS TopAnswer3_Score,
    COALESCE(urA3.DisplayName, 'Community') AS TopAnswer3_OwnerDisplayName,
    COALESCE(urA3.Reputation, 0) AS TopAnswer3_OwnerReputation,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = qd.QuestionId
        AND c.CreationDate > qd.QuestionCreationDate
    ) AS CommentCountOnQuestionAfterCreation,
    (
        SELECT SUM(v.VoteTypeId) -- Dummy calculation for performance
        FROM Votes v
        WHERE v.PostId = qd.QuestionId
        AND v.VoteTypeId IN (2, 3)
    ) AS VoteSumOnQuestion,
    REPLACE(qd.Tags, '><', ' | ') AS FormattedTags
FROM QuestionData qd
LEFT JOIN UserReputation urq ON qd.QuestionOwnerUserId = urq.UserId
LEFT JOIN TopAnswers ta1 ON qd.QuestionId = ta1.QuestionId AND ta1.rn = 1
LEFT JOIN TopAnswers ta2 ON qd.QuestionId = ta2.QuestionId AND ta2.rn = 2
LEFT JOIN TopAnswers ta3 ON qd.QuestionId = ta3.QuestionId AND ta3.rn = 3
LEFT JOIN UserReputation urA1 ON ta1.OwnerUserId = urA1.UserId
LEFT JOIN UserReputation urA2 ON ta2.OwnerUserId = urA2.UserId
LEFT JOIN UserReputation urA3 ON ta3.OwnerUserId = urA3.UserId
WHERE qd.AnswerCount > 0
  AND qd.QuestionCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND qd.ViewCount > 1000
  AND qd.FavoriteCount IS NOT NULL
  AND qd.FormattedTitle ILIKE '%SQL%'
ORDER BY qd.QuestionCreationDate DESC
LIMIT 100;