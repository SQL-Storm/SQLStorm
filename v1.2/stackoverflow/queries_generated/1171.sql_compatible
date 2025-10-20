WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Id) AS TotalBadges,
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
        AVG(p.Score) AS AvgPostScore,
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
        COALESCE(array_length(string_to_array(trim(both '<>' FROM p.Tags), '><'), 1), 0) AS TagCount,
        CASE 
            WHEN p.ViewCount IS NULL THEN 0
            ELSE p.Score * LN(p.ViewCount + 1) / GREATEST(p.AnswerCount, 1)
        END AS ComplexityScore
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopAnsweredQuestions AS (
    SELECT
        p.Id AS PostId,
        RANK() OVER (ORDER BY p.AnswerCount DESC NULLS LAST, p.Score DESC NULLS LAST) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.AnswerCount IS NOT NULL
      AND p.AnswerCount > 0
),
CloseReasonCount AS (
    SELECT
        cht.Name AS CloseReason,
        COUNT(DISTINCT ph.PostId) AS ClosedPostCount
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes cht ON CAST(ph.Comment AS integer) = cht.Id
    WHERE ph.PostHistoryTypeId = 10
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
    pc.AnswerRank AS TopQuestionAnswerRank,
    crc.CloseReason,
    crc.ClosedPostCount
FROM UserBadgeStats ubs
JOIN UserPostActivity upa ON upa.UserId = ubs.UserId
LEFT JOIN UserVoteSummary uvs ON uvs.UserId = ubs.UserId
LEFT JOIN LATERAL (
    SELECT
        taq.PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(array_length(string_to_array(trim(both '<>' FROM p.Tags), '><'), 1), 0) AS TagCount,
        CASE 
            WHEN p.ViewCount IS NULL THEN 0
            ELSE p.Score * LN(p.ViewCount + 1) / GREATEST(p.AnswerCount, 1)
        END AS ComplexityScore,
        taq.AnswerRank
    FROM TopAnsweredQuestions taq
    JOIN Posts p ON p.Id = taq.PostId
    WHERE p.OwnerUserId = ubs.UserId
    ORDER BY taq.AnswerRank
    LIMIT 1
) pc ON true
LEFT JOIN CloseReasonCount crc ON crc.CloseReason IS NOT NULL
WHERE ubs.TotalBadges > 0
  AND (upa.QuestionsCount > 10 OR upa.AnswersCount > 20)
ORDER BY ubs.BadgeScore DESC NULLS LAST, upa.AvgPostScore DESC NULLS LAST, uvs.TotalVotesCast DESC NULLS LAST
LIMIT 100;