-- {"query": "27005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1772} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT p.Id) AS UniquePosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(p.LastActivityDate) AS LastActivityDate,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        STRING_AGG(DISTINCT t.TagName, ', ') AS MostUsedTags
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Posts q ON p.Tags IS NOT NULL AND q.Id = p.ParentId
    LEFT JOIN
        Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
    WHERE
        u.Reputation > 1000
        AND u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
), TopUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        UniquePosts,
        TotalQuestions,
        TotalAnswers,
        TotalPostScore,
        LastPostDate,
        LastActivityDate,
        TotalBountyAmount,
        TotalBadges,
        MostUsedTags,
        RANK() OVER (ORDER BY TotalPostScore DESC, TotalPosts DESC) AS UserRank
    FROM
        UserActivity
), TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM
        Posts p
    JOIN
        TopUsers tu ON p.OwnerUserId = tu.UserId
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.CreationDate > NOW() - INTERVAL '1 year'
        AND p.Score > 10
), FinalResults AS (
    SELECT
        tu.UserId,
        tu.Reputation,
        tu.UserCreationDate,
        tu.TotalPosts,
        tu.UniquePosts,
        tu.TotalQuestions,
        tu.TotalAnswers,
        tu.TotalPostScore,
        tu.LastPostDate,
        tu.LastActivityDate,
        tu.TotalBountyAmount,
        tu.TotalBadges,
        tu.MostUsedTags,
        tu.UserRank,
        tp.PostId,
        tp.PostTypeId,
        tp.PostCreationDate,
        tp.PostScore,
        tp.ViewCount,
        tp.AnswerCount,
        tp.CommentCount,
        tp.FavoriteCount,
        tp.PreviousPostScore,
        tp.NextPostScore,
        tp.PostTypeName,
        tp.PostRank,
        COALESCE(ph.PostHistoryTypeId, 0) AS LastEditType,
        ph.CreationDate AS LastEditDate,
        ph.UserId AS LastEditorId,
        ph.UserDisplayName AS LastEditorName,
        LAG(tp.PostScore, 1) OVER (PARTITION BY tu.UserId ORDER BY tp.PostScore DESC) AS PrevUserPostScore,
        LEAD(tp.PostScore, 1) OVER (PARTITION BY tu.UserId ORDER BY tp.PostScore DESC) AS NextUserPostScore,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId, tp.PostTypeId ORDER BY tp.PostScore DESC) AS TypeRank
    FROM
        TopUsers tu
    JOIN
        TopPosts tp ON tu.UserId = tp.OwnerUserId
    LEFT JOIN
        PostHistory ph ON tp.PostId = ph.PostId AND ph.PostHistoryTypeId IN (5, 6, 7)
)
SELECT
    fr.UserId,
    fr.Reputation,
    fr.UserCreationDate,
    fr.TotalPosts,
    fr.UniquePosts,
    fr.TotalQuestions,
    fr.TotalAnswers,
    fr.TotalPostScore,
    fr.LastPostDate,
    fr.LastActivityDate,
    fr.TotalBountyAmount,
    fr.TotalBadges,
    fr.MostUsedTags,
    fr.UserRank,
    fr.PostId,
    fr.PostTypeId,
    fr.PostCreationDate,
    fr.PostScore,
    fr.ViewCount,
    fr.AnswerCount,
    fr.CommentCount,
    fr.FavoriteCount,
    fr.PreviousPostScore,
    fr.NextPostScore,
    fr.PostTypeName,
    fr.PostRank,
    fr.LastEditType,
    fr.LastEditDate,
    fr.LastEditorId,
    fr.LastEditorName,
    fr.PrevUserPostScore,
    fr.NextUserPostScore,
    fr.TypeRank,
    CASE
        WHEN fr.TotalPostScore > 1000 THEN 'High Performer'
        WHEN fr.TotalPostScore BETWEEN 500 AND 1000 THEN 'Mid Performer'
        ELSE 'Low Performer'
    END AS PerformanceCategory,
    CASE
        WHEN fr.TotalPosts > 500 THEN 'Highly Active'
        WHEN fr.TotalPosts BETWEEN 200 AND 500 THEN 'Moderately Active'
        ELSE 'Less Active'
    END AS ActivityLevel
FROM
    FinalResults fr
ORDER BY
    fr.UserRank,
    fr.PostRank,
    fr.TypeRank;
