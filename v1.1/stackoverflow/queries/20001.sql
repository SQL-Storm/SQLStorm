WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId IN (2, 3)) AS TotalVotesCast
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 1500
        AND u.AboutMe IS NOT NULL
        AND LENGTH(u.AboutMe) > 50
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes
    HAVING
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) > 0
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.Tags,
        p.CreationDate,
        p.AnswerCount,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.CreationDate) AS PrevPostDate,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.CreationDate) AS NextPostDate,
        (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = p.Id) AS FirstAnswerDate,
        (SELECT aa.CreationDate FROM Posts aa WHERE aa.Id = p.AcceptedAnswerId) AS AcceptedAnswerDate
    FROM
        Posts p
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.CommunityOwnedDate IS NULL
        AND p.ClosedDate IS NULL
),
UserContributionProfile AS (
    SELECT
        pd.OwnerUserId,
        COUNT(CASE WHEN pd.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
        COUNT(CASE WHEN pd.PostTypeId = 2 THEN 1 END) AS TotalAnswers,
        COALESCE(AVG(CASE WHEN pd.PostTypeId = 2 THEN pd.Score END), 0) AS AvgAnswerScore,
        COALESCE(SUM(CASE WHEN pd.PostTypeId = 1 THEN pd.ViewCount END), 0) AS TotalQuestionViews,
        COALESCE(MAX(CASE WHEN pd.PostTypeId = 2 THEN pd.Score END), 0) AS MaxAnswerScore,
        COALESCE(AVG(EXTRACT(EPOCH FROM (pd.CreationDate - pd.PrevPostDate))) / 3600, -1) AS AvgHoursBetweenPosts,
        COALESCE(AVG(EXTRACT(EPOCH FROM (pd.FirstAnswerDate - pd.CreationDate))) / 60, -1) AS AvgMinutesToFirstAnswer,
        COALESCE(AVG(EXTRACT(EPOCH FROM (pd.AcceptedAnswerDate - pd.CreationDate))) / 3600, -1) AS AvgHoursToAcceptedAnswer
    FROM
        PostDetails pd
    GROUP BY
        pd.OwnerUserId
)
SELECT
    um.DisplayName,
    um.Reputation,
    ucp.TotalQuestions,
    ucp.TotalAnswers,
    CAST(ucp.AvgAnswerScore AS DECIMAL(10, 2)) AS AvgAnswerScore,
    (CAST(um.GoldBadges AS VARCHAR) || 'G / ' || CAST(um.SilverBadges AS VARCHAR) || 'S / ' || CAST(um.BronzeBadges AS VARCHAR) || 'B') AS BadgeSummary,
    CASE
        WHEN um.Reputation > 100000 AND ucp.AvgAnswerScore > 20 THEN 'Community Leader'
        WHEN um.Reputation > 50000 AND um.GoldBadges > 10 THEN 'Expert'
        WHEN ucp.TotalAnswers > 500 THEN 'Dedicated Responder'
        ELSE 'Active Contributor'
    END AS UserTier,
    ROW_NUMBER() OVER (
        PARTITION BY
            CASE
                WHEN um.Reputation > 100000 AND ucp.AvgAnswerScore > 20 THEN 'Community Leader'
                WHEN um.Reputation > 50000 AND um.GoldBadges > 10 THEN 'Expert'
                WHEN ucp.TotalAnswers > 500 THEN 'Dedicated Responder'
                ELSE 'Active Contributor'
            END
        ORDER BY
            (um.Reputation * 0.4) + (ucp.AvgAnswerScore * 50) + (um.GoldBadges * 200) + (ucp.TotalAnswers * 1.5) DESC
    ) AS RankInTier,
    ucp.AvgHoursBetweenPosts,
    ucp.AvgHoursToAcceptedAnswer,
    (SELECT c.Text
     FROM Comments c
     WHERE c.UserId = um.UserId
     ORDER BY c.CreationDate DESC
     FETCH FIRST 1 ROW ONLY) AS LastCommentText
FROM
    UserMetrics um
JOIN
    UserContributionProfile ucp ON um.UserId = ucp.OwnerUserId
WHERE
    ucp.TotalAnswers > ucp.TotalQuestions
    AND ucp.AvgAnswerScore > 2.0
    AND (um.UpVotes / NULLIF(um.DownVotes, 1.0)) > 10.0
    AND EXISTS (
        SELECT 1
        FROM PostDetails pd
        WHERE pd.OwnerUserId = um.UserId
          AND pd.PostTypeId = 2
          AND (
                pd.Tags LIKE '%<sql>%'
             OR pd.Tags LIKE '%<performance>%'
             OR pd.Tags LIKE '%<database>%'
             OR pd.Tags LIKE '%<optimization>%'
          )
    )
ORDER BY
    UserTier, RankInTier
FETCH FIRST 200 ROWS ONLY;