WITH 
UserActivity AS (
    SELECT 
        u.Id,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id), 0
        ) AS PostCount,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id), 0
        ) AS CommentCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.UserId = u.Id AND v.VoteTypeId = 2), 0
        ) AS UpVotesGiven,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id), 0
        ) AS BadgeCount
    FROM Users u
),
BadgeScore AS (
    SELECT 
        b.UserId,
        SUM(
            CASE b.Class 
                WHEN 1 THEN 100
                WHEN 2 THEN 50
                ELSE 20
            END
        ) AS WeightedBadgeScore
    FROM Badges b
    GROUP BY b.UserId
),
PostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),
Combined AS (
    SELECT 
        u.Id,
        CONCAT(u.DisplayName, ' (', COALESCE(u.Location, 'N/A'), ')') AS FullDisplayName,
        u.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.UpVotesGiven,
        ua.BadgeCount,
        COALESCE(bs.WeightedBadgeScore, 0)        AS BadgeScore,
        COALESCE(ps.QuestionCount, 0)            AS QuestionCount,
        COALESCE(ps.AnswerCount, 0)              AS AnswerCount,
        COALESCE(ps.TotalScore, 0)               AS TotalScore,
        ps.LastPostDate,
        (ua.PostCount * 2) 
        + ua.CommentCount 
        + ua.UpVotesGiven 
        + COALESCE(bs.WeightedBadgeScore, 0) 
        + COALESCE(ps.TotalScore, 0)             AS ActivityWeight,
        ROW_NUMBER() OVER (ORDER BY 
            (ua.PostCount * 2) 
            + ua.CommentCount 
            + ua.UpVotesGiven 
            + COALESCE(bs.WeightedBadgeScore, 0) 
            + COALESCE(ps.TotalScore, 0) DESC
        )                                        AS ActivityRank
    FROM Users u
    LEFT JOIN UserActivity ua   ON ua.Id = u.Id
    LEFT JOIN BadgeScore bs     ON bs.UserId = u.Id
    LEFT JOIN PostStats ps      ON ps.UserId = u.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Location,
        u.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.UpVotesGiven,
        ua.BadgeCount,
        bs.WeightedBadgeScore,
        ps.QuestionCount,
        ps.AnswerCount,
        ps.TotalScore,
        ps.LastPostDate
)

SELECT 
    Id,
    FullDisplayName,
    Reputation,
    PostCount,
    CommentCount,
    UpVotesGiven,
    BadgeCount,
    BadgeScore,
    QuestionCount,
    AnswerCount,
    TotalScore,
    LastPostDate,
    ActivityWeight,
    ActivityRank
FROM Combined
WHERE ActivityRank <= 100

UNION ALL

SELECT 
    NULL                                   AS Id,
    'Aggregated Rest'                      AS FullDisplayName,
    NULL                                   AS Reputation,
    SUM(PostCount)                         AS PostCount,
    SUM(CommentCount)                      AS CommentCount,
    SUM(UpVotesGiven)                      AS UpVotesGiven,
    SUM(BadgeCount)                        AS BadgeCount,
    SUM(BadgeScore)                        AS BadgeScore,
    SUM(QuestionCount)                     AS QuestionCount,
    SUM(AnswerCount)                       AS AnswerCount,
    SUM(TotalScore)                        AS TotalScore,
    MAX(LastPostDate)                      AS LastPostDate,
    NULL                                   AS ActivityWeight,
    NULL                                   AS ActivityRank
FROM Combined
WHERE ActivityRank > 100

ORDER BY 
    ActivityRank NULLS LAST,
    Reputation DESC
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY;