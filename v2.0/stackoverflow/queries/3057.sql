-- {"query": "3057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2224} 
WITH 
    top_users AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.Location, 'Unknown') AS Location,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
        FROM Users u
        WHERE u.Reputation > 10000
    ),
    user_badge_counts AS (
        SELECT 
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
            COUNT(*) AS total
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_questions AS (
        SELECT 
            p.Id,
            p.Title,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.OwnerUserId,
            p.Tags,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1               -- Question
          AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    ),
    latest_comment_per_post AS (
        SELECT 
            c.PostId,
            c.Text AS LatestComment,
            c.CreationDate AS CommentDate
        FROM Comments c
        WHERE c.CreationDate = (
            SELECT MAX(c2.CreationDate)
            FROM Comments c2
            WHERE c2.PostId = c.PostId
        )
    ),
    tag_usage AS (
        SELECT 
            trim(both '<>' FROM unnest(string_to_array(p.Tags, '><'))) AS Tag,
            COUNT(*) AS UsageCount,
            AVG(p.Score) AS AvgScore
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
        GROUP BY 1
    ),
    recent_activity AS (
        SELECT 
            u.Id AS UserId,
            u.DisplayName,
            COALESCE(ub.gold,0) AS GoldBadges,
            COALESCE(ub.silver,0) AS SilverBadges,
            COALESCE(ub.bronze,0) AS BronzeBadges,
            COALESCE(ub.total,0) AS TotalBadges,
            rq.Id AS RecentQuestionId,
            rq.Title AS RecentQuestionTitle,
            rq.Score AS RecentQuestionScore,
            lc.LatestComment,
            lc.CommentDate,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY rq.CreationDate DESC NULLS LAST) AS QRank
        FROM top_users u
        LEFT JOIN user_badge_counts ub      ON ub.UserId = u.Id
        LEFT JOIN recent_questions rq      ON rq.OwnerUserId = u.Id AND rq.rn = 1
        LEFT JOIN latest_comment_per_post lc ON lc.PostId = rq.Id
    )
SELECT 
    ra.UserId,
    ra.DisplayName,
    ra.GoldBadges,
    ra.SilverBadges,
    ra.BronzeBadges,
    ra.TotalBadges,
    ra.RecentQuestionId,
    ra.RecentQuestionTitle,
    ra.RecentQuestionScore,
    COALESCE(ra.LatestComment, '(No comments)') AS LatestComment,
    ra.CommentDate,
    CASE 
        WHEN ra.RecentQuestionScore IS NULL THEN NULL
        WHEN ra.RecentQuestionScore >= 10 THEN 'Hot'
        WHEN ra.RecentQuestionScore >= 5  THEN 'Warm'
        ELSE 'Cold'
    END AS QuestionHeat,
    tu.Tag,
    tu.UsageCount,
    tu.AvgScore
FROM recent_activity ra
LEFT JOIN tag_usage tu 
    ON tu.Tag = ANY (
        string_to_array(
            COALESCE(
                (SELECT p.Tags FROM Posts p WHERE p.Id = ra.RecentQuestionId),
                ''
            ),
            '><'
        )
    )
WHERE ra.QRank = 1
ORDER BY ra.GoldBadges DESC, ra.SilverBadges DESC, ra.BronzeBadges DESC, ra.UserId;