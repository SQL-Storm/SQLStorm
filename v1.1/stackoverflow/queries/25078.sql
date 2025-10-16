WITH RECURSIVE TagTree AS (
    SELECT 
        p.Id                AS QuestionId,
        unnest(string_to_array(
                regexp_replace(p.Tags, '^<|>$', '', 'g'), 
                '><'))        AS Tag,
        1                   AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    UNION ALL
    SELECT 
        tt.QuestionId,
        t.TagName,
        tt.Depth + 1
    FROM TagTree tt
    JOIN Tags t ON t.TagName = tt.Tag
    WHERE tt.Depth < 3
),

UserStats AS (
    SELECT 
        u.Id                                    AS UserId,
        u.DisplayName,
        COALESCE(u.Reputation,0)                AS Reputation,
        COUNT(DISTINCT p.Id)                    AS QuestionCount,
        COUNT(DISTINCT a.Id)                    AS AnswerCount,
        SUM(COALESCE(p.Score,0))                AS QuestionScore,
        SUM(COALESCE(a.Score,0))                AS AnswerScore,
        SUM(COALESCE(v.UpVoteCnt,0) - COALESCE(v.DownVoteCnt,0)) AS VoteBalance,
        COUNT(DISTINCT b.Id)                    AS BadgeCount,
        MAX(u.CreationDate)                     AS FirstSeen,
        MAX(p.LastActivityDate)                 AS LastQuestionActivity,
        MAX(a.LastActivityDate)                 AS LastAnswerActivity
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a   ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN (
        SELECT 
            v.PostId AS VoteId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCnt,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCnt
        FROM Votes v
        GROUP BY v.PostId
    ) v ON v.VoteId = COALESCE(p.Id, a.Id)
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TopContributors AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.QuestionScore,
        us.AnswerScore,
        us.VoteBalance,
        us.BadgeCount,
        us.FirstSeen,
        us.LastQuestionActivity,
        us.LastAnswerActivity,
        RANK() OVER (ORDER BY 
            (us.QuestionScore * 2 
            + us.AnswerScore * 3 
            + us.VoteBalance * 0.5 
            + us.BadgeCount * 10) DESC) AS RankScore,
        (us.QuestionScore * 2 
            + us.AnswerScore * 3 
            + us.VoteBalance * 0.5 
            + us.BadgeCount * 10)         AS CompositeScore
    FROM UserStats us
    WHERE us.Reputation > 1000
),

RecentClosedQuestions AS (
    SELECT 
        p.Id               AS QuestionId,
        p.Title,
        p.CreationDate,
        ph.CreationDate    AS ClosedDate,
        COALESCE(crt.Name, 'unknown') AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph 
        ON ph.PostId = p.Id 
       AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt 
        ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE p.PostTypeId = 1
      AND ph.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')
),

LinkedDuplicates AS (
    SELECT pl.PostId        AS SourceId,
           pl.RelatedPostId AS TargetId,
           lt.Name          AS LinkType
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
    UNION ALL
    SELECT pl.RelatedPostId AS SourceId,
           pl.PostId        AS TargetId,
           lt.Name          AS LinkType
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),

UserTagAffinity AS (
    SELECT 
        a.OwnerUserId      AS UserId,
        tt.Tag,
        COUNT(*)           AS AnswersOnTag,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts a
    JOIN TagTree tt 
        ON tt.QuestionId = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId, tt.Tag
),

FinalReport AS (
    SELECT 
        tc.UserId,
        tc.DisplayName,
        tc.Reputation,
        tc.CompositeScore,
        tc.RankScore,
        COALESCE(rc.QuestionId, 0)          AS LatestClosedQuestionId,
        rc.Title                            AS LatestClosedTitle,
        rc.CloseReason                      AS LatestCloseReason,
        ld.SourceId                         AS DuplicateOf,
        ld.TargetId                         AS DuplicateTarget,
        uta.Tag,
        uta.AnswersOnTag,
        CASE 
            WHEN uta.Tag IS NULL THEN 'None'
            ELSE 'Yes' 
        END                               AS HasTagAffinity
    FROM TopContributors tc
    LEFT JOIN LATERAL (
        SELECT *
        FROM RecentClosedQuestions rc
        WHERE rc.QuestionId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = tc.UserId
              AND p.PostTypeId = 1
            ORDER BY p.CreationDate DESC
            LIMIT 1
        ) AND rc.rn = 1
    ) rc ON TRUE
    LEFT JOIN LATERAL (
        SELECT *
        FROM LinkedDuplicates ld
        WHERE ld.SourceId = rc.QuestionId
        ORDER BY ld.TargetId
        LIMIT 1
    ) ld ON TRUE
    LEFT JOIN LATERAL (
        SELECT *
        FROM UserTagAffinity uta
        WHERE uta.UserId = tc.UserId
          AND uta.TagRank = 1
    ) uta ON TRUE
)

SELECT *
FROM FinalReport
ORDER BY CompositeScore DESC
LIMIT 20;