-- {"query": "1082.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1538} 
WITH RecentHighlyVotedAnswers AS (
    SELECT
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore
    FROM Posts p
    WHERE p.PostTypeId = 2 -- Answer
      AND p.CreationDate > NOW() - INTERVAL '180 days'
      AND p.Score >= 10
),
TopQuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId AS QuestionOwner,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.CreationDate AS QuestionCreationDate,
        rha.Id AS AnswerId,
        rha.OwnerUserId AS AnswerOwner,
        rha.Score AS AnswerScore,
        rha.CreationDate AS AnswerCreationDate
    FROM Posts q
    LEFT JOIN RecentHighlyVotedAnswers rha ON rha.ParentId = q.Id AND rha.RankByScore = 1
    WHERE q.PostTypeId = 1 -- Question
      AND q.Score >= 20
      AND (q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<performance>%')
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserReputationWindows AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubc.TotalBadges, 0) AS TotalBadges,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        LEAD(u.Reputation) OVER (ORDER BY u.Reputation DESC) AS NextHigherReputation,
        LAG(u.Reputation) OVER (ORDER BY u.Reputation DESC) AS PrevLowerReputation
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    WHERE u.Reputation >= 1000
),
QuestionCloseInfo AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
UserTopTags AS (
    SELECT
        u.Id AS UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS PostCount
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 -- Question
      AND p.OwnerUserId IS NOT NULL
    GROUP BY u.Id, Tag
),
UserDominantTag AS (
    SELECT DISTINCT ON (ut.UserId)
        ut.UserId,
        ut.Tag,
        ut.PostCount
    FROM UserTopTags ut
    ORDER BY ut.UserId, ut.PostCount DESC
),
AggregatedVotes AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
FinalSelection AS (
    SELECT
        tq.QuestionId,
        tq.Title,
        COALESCE(asi.AnswerScore, 0) AS TopAnswerScore,
        COALESCE(asi.AnswerCreationDate, tq.QuestionCreationDate) AS TopAnswerCreationDate,
        tq.QuestionScore,
        tq.ViewCount,
        qci.CloseReason,
        u.DisplayName AS QuestionOwnerName,
        urw.ReputationRank,
        urw.GoldBadges,
        urw.SilverBadges,
        urw.BronzeBadges,
        urw.TotalBadges,
        udt.Tag AS UserDominantTag,
        av.UpVotes,
        av.DownVotes,
        av.Favorites,
        CASE
            WHEN qci.CloseReason IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS IsClosed
    FROM TopQuestionsWithAnswers tq
    LEFT JOIN AggregatedVotes av ON av.PostId = tq.QuestionId
    LEFT JOIN AggregatedVotes asi ON asi.PostId = tq.AnswerId
    LEFT JOIN QuestionCloseInfo qci ON qci.PostId = tq.QuestionId
    LEFT JOIN Users u ON u.Id = tq.QuestionOwner
    LEFT JOIN UserReputationWindows urw ON urw.Id = tq.QuestionOwner
    LEFT JOIN UserDominantTag udt ON udt.UserId = tq.QuestionOwner
    WHERE tq.AnswerId IS NOT NULL
),
UnionExtraQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        0 AS TopAnswerScore,
        p.CreationDate AS TopAnswerCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        NULL::varchar(50) AS CloseReason,
        u.DisplayName AS QuestionOwnerName,
        urw.ReputationRank,
        urw.GoldBadges,
        urw.SilverBadges,
        urw.BronzeBadges,
        urw.TotalBadges,
        NULL::varchar(35) AS UserDominantTag,
        av.UpVotes,
        av.DownVotes,
        av.Favorites,
        FALSE AS IsClosed
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserReputationWindows urw ON urw.Id = p.OwnerUserId
    LEFT JOIN AggregatedVotes av ON av.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.Score >= 50
      AND p.Id NOT IN (SELECT QuestionId FROM FinalSelection)
)
SELECT
    *
FROM (
    SELECT * FROM FinalSelection
    UNION
    SELECT * FROM UnionExtraQuestions
) all_questions
WHERE (IsClosed = FALSE OR CloseReason LIKE '%Duplicate%')
  AND (
      (GoldBadges > 2 AND QuestionScore > 50) OR
      (TotalBadges > 10 AND ViewCount > 1000) OR
      (UserDominantTag IS NOT NULL AND TopAnswerScore > 15)
  )
ORDER BY ReputationRank NULLS LAST, QuestionScore DESC, TopAnswerScore DESC
LIMIT 100;