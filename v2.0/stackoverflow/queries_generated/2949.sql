-- {"query": "2949.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2016} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.Score DESC) AS TagTopPostRank
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%') AND p.PostTypeId = 1
    WHERE t.IsRequired = 0

    UNION ALL

    SELECT 
        rh.Id,
        rh.TagName,
        rh.Count,
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        rh.TagTopPostRank
    FROM RecursiveTagHierarchy rh
    JOIN Posts p ON p.ParentId = rh.PostId AND p.PostTypeId = 2
    WHERE rh.TagTopPostRank <= 5
),
UserActivityRankings AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COALESCE(SUM(vb.UpVotes), 0) AS TotalUpVotes,
        COALESCE(SUM(vb.DownVotes), 0) AS TotalDownVotes,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            p.OwnerUserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) vb ON vb.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
QuestionCloseStats AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseCount,
        MAX(CAST(ph.Comment AS INT)) FILTER (WHERE ph.PostHistoryTypeId = 10 AND ISNUMERIC(ph.Comment) = 1) AS MostCommonCloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
TopClosedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        qcs.CloseCount,
        crt.Name AS CloseReasonName,
        p.Score,
        p.ViewCount
    FROM Posts p
    LEFT JOIN QuestionCloseStats qcs ON qcs.PostId = p.Id
    LEFT JOIN CloseReasonTypes crt ON crt.Id = qcs.MostCommonCloseReasonId
    WHERE p.PostTypeId = 1 
      AND qcs.CloseCount > 0
    ORDER BY qcs.CloseCount DESC, p.ViewCount DESC
    LIMIT 10
),
AnswersWithUpvoteRatio AS (
  SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId,
      a.Score,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
      CASE 
          WHEN COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0) = 0 THEN NULL
          ELSE ROUND(COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0)::decimal / NULLIF(COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0), 0), 3) 
      END AS UpvoteRatio
  FROM Posts a
  LEFT JOIN Votes v ON v.PostId = a.Id
  WHERE a.PostTypeId = 2
  GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score
),
RankedAnswers AS (
    SELECT 
        a.*,
        ROW_NUMBER() OVER (PARTITION BY a.QuestionId ORDER BY a.UpvoteRatio DESC NULLS LAST, a.Score DESC) AS AnswerRankByUpvoteRatio
    FROM AnswersWithUpvoteRatio a
),
QuestionsWithTopAnswerInfo AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        ra.AnswerId,
        ra.UpVotes,
        ra.DownVotes,
        ra.UpvoteRatio,
        ra.AnswerRankByUpvoteRatio
    FROM Posts q
    LEFT JOIN RankedAnswers ra ON ra.QuestionId = q.Id AND ra.AnswerRankByUpvoteRatio = 1
    WHERE q.PostTypeId = 1
),
UserBadgesSummary AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT CONCAT(b.Name, '(', CASE WHEN b.Class=1 THEN 'Gold' WHEN b.Class=2 THEN 'Silver' ELSE 'Bronze' END, ')'), ', ') AS BadgeList,
        COUNT(DISTINCT b.Name) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserDetailedStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        COALESCE(ub.BadgeCount, 0) AS TotalBadges,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        ub.BadgeList,
        ua.ActivityRank
    FROM Users u
    LEFT JOIN UserActivityRankings ua ON ua.UserId = u.Id
    LEFT JOIN UserBadgesSummary ub ON ub.UserId = u.Id
),
TaggedPostsAnalysis AS (
    SELECT
        rh.TagName,
        COUNT(DISTINCT rh.PostId) AS PostCount,
        AVG(rh.Score) AS AvgScore,
        MAX(rh.Score) AS MaxScore,
        MIN(rh.Score) AS MinScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE rh.Score = MAX(rh.Score) OVER (PARTITION BY rh.TagName)) AS TopPostOwners
    FROM RecursiveTagHierarchy rh
    LEFT JOIN Users u ON u.Id = rh.OwnerUserId
    GROUP BY rh.TagName
)
SELECT
    td.TagName,
    td.PostCount,
    td.AvgScore,
    td.MaxScore,
    td.MinScore,
    COALESCE(td.TopPostOwners, 'N/A') AS TopPostOwners,
    qta.QuestionId,
    qta.Title AS QuestionTitle,
    qta.CreationDate AS QuestionCreation,
    qta.QuestionScore,
    qta.AnswerId AS TopAnswerId,
    qta.UpVotes AS TopAnswerUpVotes,
    qta.DownVotes AS TopAnswerDownVotes,
    qta.UpvoteRatio AS TopAnswerUpvoteRatio,
    uds.DisplayName AS TopAnswerOwner,
    uds.Reputation AS TopAnswerOwnerReputation,
    uds.Location AS TopAnswerOwnerLocation,
    uds.TotalBadges AS TopAnswerOwnerTotalBadges,
    uds.GoldBadges AS TopAnswerOwnerGoldBadges,
    uds.SilverBadges AS TopAnswerOwnerSilverBadges,
    uds.BronzeBadges AS TopAnswerOwnerBronzeBadges
FROM TaggedPostsAnalysis td
LEFT JOIN QuestionsWithTopAnswerInfo qta ON qta.QuestionId IN (
    SELECT p.Id FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE CONCAT('%<', td.TagName, '>%') ORDER BY p.Score DESC LIMIT 1
)
LEFT JOIN Users uds ON uds.UserId = qta.OwnerUserId
WHERE td.PostCount > 20
ORDER BY td.AvgScore DESC
LIMIT 25

UNION ALL

SELECT
    'Top Closed Questions' AS TagName,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    tcq.QuestionId,
    tcq.Title,
    tcq.CreationDate,
    tcq.Score,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM TopClosedQuestions tcq
ORDER BY TagName, QuestionId;
