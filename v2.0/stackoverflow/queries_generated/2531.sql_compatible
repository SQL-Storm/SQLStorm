WITH RecursiveTagCounts AS (
    SELECT
        u.Id AS UserId,
        lower(trim(tag)) AS Tag,
        COUNT(*) AS TagUsageCount
    FROM
        Users u
        JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
        ) AS taglist
    GROUP BY u.Id, lower(trim(tag))
),
UserBadges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges
    GROUP BY UserId
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
UserPostActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        COUNT(c.Id) AS CommentCount,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
UserTopTags AS (
    SELECT
        rtc.UserId,
        rtc.Tag,
        rtc.TagUsageCount,
        ROW_NUMBER() OVER (PARTITION BY rtc.UserId ORDER BY rtc.TagUsageCount DESC) AS rn
    FROM RecursiveTagCounts rtc
),
UserRankedTags AS (
    SELECT
        UserId,
        string_agg(Tag, ', ') AS TopTags
    FROM UserTopTags
    WHERE rn <= 3
    GROUP BY UserId
),
PostCloseReasons AS (
    SELECT 
        ph.UserId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostHistoryTypeId = 10 AND crt.Id IS NOT NULL
    GROUP BY ph.UserId, crt.Name
),
UserVoteStats AS (
    -- rewritten to avoid non-inner join on subquery by aggregating votes separately
    SELECT
        u.Id,
        COALESCE(g.VotesGiven, 0) AS VotesGiven,
        COALESCE(r.VotesReceived, 0) AS VotesReceived
    FROM Users u
    LEFT JOIN (
        SELECT v.UserId, COUNT(*) AS VotesGiven
        FROM Votes v
        WHERE v.UserId IS NOT NULL
        GROUP BY v.UserId
    ) g ON g.UserId = u.Id
    LEFT JOIN (
        SELECT p.OwnerUserId AS OwnerUserId, COUNT(v.Id) AS VotesReceived
        FROM Votes v
        JOIN Posts p ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) r ON r.OwnerUserId = u.Id
)
SELECT
    upa.Id AS UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.CreationDate,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.CommentCount,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ub.TagBasedBadges, 0) AS TagBasedBadges,
    urt.TopTags,
    COALESCE(uv.VotesGiven, 0) AS VotesGiven,
    COALESCE(uv.VotesReceived, 0) AS VotesReceived,
    COALESCE(pas.AvgAnswerScore, 0) AS AvgAnswerScoreOnQuestions,
    COALESCE(pas.AnswerCount, 0) AS TotalAnswersOnQuestions,
    COALESCE(pcr.CloseCount, 0) AS PostClosuresCast,
    pcr.CloseReasonName,
    DENSE_RANK() OVER (ORDER BY upa.Reputation DESC) AS ReputationRank,
    (CASE
        WHEN upa.Reputation > 100000 THEN 'Legendary'
        WHEN upa.Reputation > 10000 THEN 'Expert'
        WHEN upa.Reputation > 1000 THEN 'Intermediate'
        WHEN upa.Reputation > 100 THEN 'Beginner'
        ELSE 'Newbie'
    END) || ' (' || COALESCE(urt.TopTags, 'no-tags') || ')' AS UserStatusWithTopTags
FROM
    UserPostActivity upa
    LEFT JOIN UserBadges ub ON ub.UserId = upa.Id
    LEFT JOIN UserRankedTags urt ON urt.UserId = upa.Id
    LEFT JOIN UserVoteStats uv ON uv.Id = upa.Id
    LEFT JOIN PostAnswerStats pas ON pas.QuestionId = (
        SELECT Id FROM Posts
        WHERE OwnerUserId = upa.Id AND PostTypeId = 1
        ORDER BY Score DESC NULLS LAST LIMIT 1
    )
    LEFT JOIN PostCloseReasons pcr ON pcr.UserId = upa.Id
WHERE 
    upa.Reputation IS NOT NULL
    AND (COALESCE(upa.QuestionCount,0) + COALESCE(upa.AnswerCount,0)) > 10
ORDER BY
    upa.Reputation DESC,
    VotesReceived DESC NULLS LAST
LIMIT 50;