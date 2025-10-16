-- {"query": "1171.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1286} 
WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        -- Weighted badge score
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) * 3
            + COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) * 2
            + COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) * 1 AS BadgeScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        AVG(p.Score)::numeric(10,2) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
PostComplexStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Title,
        p.Tags,
        -- Calculate tag count by splitting Tags string, handling NULL
        COALESCE(array_length(string_to_array(trim(both '<>' FROM p.Tags), '><'), 1), 0) AS TagCount,
        -- Generate a complexity score: Score * log(ViewCount+1) / (1 + AnswerCount)
        CASE 
            WHEN p.ViewCount IS NULL THEN 0
            ELSE p.Score * LN(p.ViewCount + 1) / GREATEST(p.AnswerCount, 1)
        END AS ComplexityScore
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only questions
),
TopAnsweredQuestions AS (
    SELECT
        PostId,
        Rank() OVER (ORDER BY AnswerCount DESC NULLS LAST, Score DESC NULLS LAST) AS AnswerRank
    FROM Posts
    WHERE PostTypeId = 1 -- Questions only
    AND AnswerCount IS NOT NULL
    AND AnswerCount > 0
),
CloseReasonCount AS (
    SELECT
        cht.Name AS CloseReason,
        COUNT(DISTINCT ph.PostId) AS ClosedPostCount
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes cht ON CAST(ph.Comment AS int) = cht.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY cht.Name
),
UserVoteSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(v.Id) AS TotalVotesCast,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyGiven
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    ubs.UserId,
    ubs.DisplayName,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.BadgeScore,
    upa.QuestionsCount,
    upa.AnswersCount,
    COALESCE(upa.AvgPostScore, 0) AS AvgPostScore,
    upa.LastPostDate,
    uvs.UpVotes,
    uvs.DownVotes,
    uvs.TotalVotesCast,
    uvs.TotalBountyGiven,
    pc.PostId AS TopQuestionId,
    pc.Title AS TopQuestionTitle,
    pc.Score AS TopQuestionScore,
    pc.ViewCount AS TopQuestionViews,
    pc.AnswerCount AS TopQuestionAnswerCount,
    pc.TagCount AS TopQuestionTagCount,
    pc.ComplexityScore AS TopQuestionComplexityScore,
    tcp.AnswerRank AS TopQuestionAnswerRank,
    crc.CloseReason,
    crc.ClosedPostCount
FROM UserBadgeStats ubs
JOIN UserPostActivity upa ON upa.UserId = ubs.UserId
LEFT JOIN UserVoteSummary uvs ON uvs.UserId = ubs.UserId
LEFT JOIN LATERAL (
    SELECT TOPAnsweredQuestions.PostId,
           Posts.Title,
           Posts.Score,
           Posts.ViewCount,
           Posts.AnswerCount,
           COALESCE(array_length(string_to_array(trim(both '<>' FROM Posts.Tags), '><'), 1), 0) AS TagCount,
           CASE 
               WHEN Posts.ViewCount IS NULL THEN 0
               ELSE Posts.Score * LN(Posts.ViewCount + 1) / GREATEST(Posts.AnswerCount, 1)
           END AS ComplexityScore,
           TOPAnsweredQuestions.AnswerRank
    FROM TOPAnsweredQuestions
    JOIN Posts ON Posts.Id = TOPAnsweredQuestions.PostId
    WHERE Posts.OwnerUserId = ubs.UserId
    ORDER BY TOPAnsweredQuestions.AnswerRank
    LIMIT 1
) pc ON true
LEFT JOIN CloseReasonCount crc ON crc.CloseReason IS NOT NULL
WHERE ubs.TotalBadges > 0
  AND (upa.QuestionsCount > 10 OR upa.AnswersCount > 20)
ORDER BY ubs.BadgeScore DESC NULLS LAST, upa.AvgPostScore DESC NULLS LAST, uvs.TotalVotesCast DESC NULLS LAST
LIMIT 100;