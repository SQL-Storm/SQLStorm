-- {"query": "9068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 5312} 

WITH RecentHistory AS (
    SELECT ph.PostId,
           MAX(ph.CreationDate) AS LastActivity
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserBadgeStats AS (
    SELECT u.Id AS UserId,
           COUNT(b.Id) AS TotalBadges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
QuestionStats AS (
    SELECT q.Id        AS QuestionId,
           q.Title,
           q.CreationDate,
           q.ViewCount,
           q.Score,
           q.Tags,
           COALESCE(c.Cnt, 0)    AS CommentCount,
           COALESCE(v.UpVotes, 0)    AS UpVotes,
           COALESCE(v.DownVotes, 0)  AS DownVotes,
           CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer
    FROM Posts q
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS Cnt
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = q.Id
    LEFT JOIN (
        SELECT v2.PostId,
               SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)    AS UpVotes,
               SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END)  AS DownVotes
        FROM Votes v2
        JOIN VoteTypes vt ON vt.Id = v2.VoteTypeId
        GROUP BY v2.PostId
    ) v ON v.PostId = q.Id
    WHERE q.PostTypeId = 1
),
RankedAnswers AS (
    SELECT a.ParentId AS QuestionId,
           a.Score,
           ROW_NUMBER() OVER (
               PARTITION BY a.ParentId
               ORDER BY a.Score DESC, a.CreationDate ASC
           ) AS RankInAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswers AS (
    SELECT QuestionId
    FROM RankedAnswers
    WHERE RankInAnswers = 1
      AND Score > 5
),
ViewedQuestions AS (
    SELECT QuestionId
    FROM QuestionStats
    WHERE ViewCount > 1000
),
FilteredQuestions AS (
    (SELECT QuestionId FROM ViewedQuestions)
    EXCEPT
    (SELECT QuestionId FROM TopAnswers)
    INTERSECT
    (SELECT QuestionId FROM QuestionStats WHERE HasAcceptedAnswer)
),
FinalQuestions AS (
    SELECT qs.*
    FROM QuestionStats qs
    JOIN FilteredQuestions fq ON fq.QuestionId = qs.QuestionId
)
SELECT
    fq.QuestionId,
    COALESCE(fq.Title,'[No Title]') || ' [' || fq.Score::text || ' pts]' AS DisplayTitle,
    u.DisplayName,
    u.Reputation,
    u.CreationDate            AS MemberSince,
    fb.GoldBadges,
    fb.SilverBadges,
    fb.BronzeBadges,
    fq.ViewCount,
    fq.CommentCount,
    fq.UpVotes - fq.DownVotes  AS VoteDelta,
    CASE WHEN fq.HasAcceptedAnswer THEN (
        SELECT COUNT(*)
        FROM Posts ans
        WHERE ans.ParentId = fq.QuestionId
          AND ans.Score > fq.Score/2
    ) ELSE NULL END            AS HighScoringAnswerCount,
    ROW_NUMBER() OVER (
        ORDER BY fq.ViewCount DESC, fq.Score DESC
    )                          AS GlobalRank,
    DENSE_RANK() OVER (
        PARTITION BY u.Id
        ORDER BY fq.CreationDate DESC
    )                          AS UserRecentRank
FROM FinalQuestions fq
FULL OUTER JOIN Posts p     ON p.Id = fq.QuestionId
RIGHT JOIN Users u          ON u.Id = p.OwnerUserId
INNER JOIN UserBadgeStats fb ON fb.UserId = u.Id
WHERE EXISTS (
    SELECT 1
    FROM UNNEST(
        string_to_array(
            substring(fq.Tags, 2, length(fq.Tags)-2)
        , '><')
    ) AS tagname(tag)
    JOIN Tags t ON t.TagName = tag
    WHERE t.Count >= 50
)
ORDER BY GlobalRank, VoteDelta DESC;
