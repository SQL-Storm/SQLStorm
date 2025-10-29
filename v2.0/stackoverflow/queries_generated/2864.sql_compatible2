with RecursiveCTE as (
    select 
        p.Id as PostId, 
        p.Score, 
        p.ViewCount,
        u.Reputation as OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
), TopQuestionsPerUser as (
    select PostId, Score, ViewCount, OwnerReputation
    from RecursiveCTE
    where rn = 1
), QuestionAnswerStats as (
    select 
        q.PostId as QuestionId,
        q.Score as QuestionScore,
        coalesce(a.AnswerCount, 0) as TotalAnswers,
        coalesce(avg_ans.Score, 0) as AvgAnswerScore,
        max_ans.Score as MaxAnswerScore,
        stragg.AnswerOwners
    from TopQuestionsPerUser q
    left join (
        select ParentId, count(*) AnswerCount
        from Posts where PostTypeId = 2
        group by ParentId
    ) a on q.PostId = a.ParentId
    left join (
        select ParentId, avg(CAST(Score AS numeric)) as Score
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) avg_ans on q.PostId = avg_ans.ParentId
    left join (
        select ParentId, max(Score) as Score
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) max_ans on q.PostId = max_ans.ParentId
    left join (
        select 
            ParentId, 
            string_agg(u.DisplayName || '(' || CAST(p.Score AS text) || ')', ', ' ORDER BY p.Score DESC) as AnswerOwners
        from Posts p
        left join Users u on p.OwnerUserId = u.Id
        where p.PostTypeId = 2
        group by ParentId
    ) stragg on q.PostId = stragg.ParentId
), BadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
), UserScores as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        case 
            when u.Reputation = 0 then NULL
            else (CAST(coalesce(bc.GoldBadges,0) AS double precision) * 5 + coalesce(bc.SilverBadges,0) * 3 + coalesce(bc.BronzeBadges,0)) / u.Reputation
        end as BadgeScoreRatio
    from Users u
    left join BadgeCounts bc on u.Id = bc.UserId
), CloseVotesAgg as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVoteCount,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenVoteCount,
        max(ph.CreationDate) as LastCloseOrReopen
    from PostHistory ph
    group by ph.PostId
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id and lower(lt.Name) like '%duplicate%'
), ComplexStringFilteredTags as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        CASE 
            WHEN lower(t.TagName) ~ '^[a-z]+(-[a-z]+)*$' THEN 'Hyphenated Lowercase' 
            WHEN t.TagName ~ '^[A-Z]+$' THEN 'AllCaps' 
            ELSE 'Other'
        END as TagPattern,
        length(t.TagName) as TagLength,
        coalesce(tp.Name, 'Unknown') as TagPostType
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    left join PostTypes tp on p.PostTypeId = tp.Id
    where t.Count > 10
), FinalSelected as (
    select 
        q.QuestionId,
        q.QuestionScore,
        q.TotalAnswers,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.AnswerOwners,
        post_owner.DisplayName as OwnerName,
        post_owner.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.BadgeScoreRatio,
        cv.CloseVoteCount,
        cv.ReopenVoteCount,
        cv.LastCloseOrReopen,
        coalesce(dl.RelatedPostId, -1) as DuplicateOfPostId,
        tft.TagName,
        tft.TagPattern,
        tft.TagLength,
        tft.TagPostType,
        case when q.QuestionScore is null then null
            else ln(abs(q.QuestionScore) + 2) * 
                 (coalesce(cv.CloseVoteCount, 0) + 1) / 
                 NULLIF((post_owner.Reputation + 100), 0)
        end as WeightedComplexScore,
        rank() over (
            partition by tft.TagPattern 
            order by case when q.QuestionScore is null then 0 else q.QuestionScore end desc
        ) as RankWithinTagPattern
    from QuestionAnswerStats q
    left join Posts p2 on p2.Id = q.QuestionId
    left join Users post_owner on post_owner.Id = p2.OwnerUserId
    left join UserScores us on us.UserId = post_owner.Id
    left join CloseVotesAgg cv on q.QuestionId = cv.PostId
    left join DuplicateLinks dl on q.QuestionId = dl.PostId
    left join ComplexStringFilteredTags tft on position('<' || tft.TagName || '>' in coalesce(p2.Tags, '')) > 0
    where q.TotalAnswers > 0
)
select *
from FinalSelected
where RankWithinTagPattern <= 10
order by WeightedComplexScore desc NULLS LAST, QuestionScore desc
limit 100;