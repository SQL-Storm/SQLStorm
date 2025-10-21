WITH QuestionRanks AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        u.Id AS OwnerUserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS MonthlyRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
),
TopQuestions AS (
    SELECT * FROM QuestionRanks WHERE MonthlyRank <= 5
),
AnswerScores AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(COALESCE(vt_up.UpVotes, 0)) AS TotalUpVotesOnAnswers,
        SUM(COALESCE(vt_down.DownVotes, 0)) AS TotalDownVotesOnAnswers
    FROM Posts a
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS UpVotes 
      FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId
    ) vt_up ON vt_up.PostId = a.Id
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS DownVotes
      FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId
    ) vt_down ON vt_down.PostId = a.Id    
    WHERE a.PostTypeId = 2 
      AND a.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY a.ParentId
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY b.UserId
),
CommentsSummary AS (
    SELECT 
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1,2) AND c.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY p.Id
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year' THEN p.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year' THEN p.Id END) AS AnswersCount,
        COUNT(DISTINCT CASE WHEN c.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year' THEN c.Id END) AS CommentsCount,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        u.Reputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN BadgeSummary bs ON bs.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
),
PostWithTags AS (
    SELECT 
      p.Id,
      p.Title,
      p.Tags,
      UNNEST(REGEXP_SPLIT_TO_ARRAY(TRIM(BOTH '><' FROM p.Tags), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagPopularity AS (
    SELECT 
        Tag,
        COUNT(*) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViews
    FROM PostWithTags pwt
    JOIN Posts p ON p.Id = pwt.Id
    WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY Tag
),
FinalSelection AS (
    SELECT 
        tq.QuestionId,
        tq.Title,
        tq.Score AS QuestionScore,
        tq.ViewCount,
        tq.DisplayName AS OwnerName,
        tq.Reputation AS OwnerReputation,
        COALESCE(ans.AnswerCount, 0) AS AnswerCount,
        COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ans.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(com.CommentCount, 0) AS CommentCount,
        COALESCE(com.AvgCommentScore, 0) AS AvgCommentScore,
        COALESCE(bad.GoldBadges, 0) AS OwnerGoldBadges,
        COALESCE(bad.SilverBadges, 0) AS OwnerSilverBadges,
        COALESCE(bad.BronzeBadges, 0) AS OwnerBronzeBadges,
        tp.Tag,
        tp.QuestionCount AS TagQuestionCount,
        tp.AvgQuestionScore AS TagAvgScore,
        tp.TotalViews AS TagTotalViews
    FROM TopQuestions tq
    LEFT JOIN AnswerScores ans ON ans.QuestionId = tq.QuestionId
    LEFT JOIN CommentsSummary com ON com.PostId = tq.QuestionId
    LEFT JOIN BadgeSummary bad ON bad.UserId = tq.OwnerUserId
    LEFT JOIN PostWithTags pwt ON pwt.Id = tq.QuestionId
    LEFT JOIN TagPopularity tp ON tp.Tag = pwt.Tag
)
SELECT *
FROM FinalSelection
ORDER BY OwnerReputation DESC, QuestionScore DESC, TagQuestionCount DESC
LIMIT 100;