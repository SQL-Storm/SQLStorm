-- {"query": "1446.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1551} 
with RecursiveTagAliases as (
    select
        t.Id,
        t.TagName,
        tags_lower.TagName as LowerTagName
    from
        Tags t
        left join Tags tags_lower on lower(t.TagName) = tags_lower.TagName
),
RecentAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        u.Reputation as OwnerReputation,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as Upvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as Downvotes,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as RankByScore,
        dense_rank() over (partition by GREATEST(p.ParentId, 0) order by p.CreationDate desc) as RankByRecent
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
        left join Comments c on c.PostId = p.Id
        left join Votes v on v.PostId = p.Id
    where
        p.PostTypeId = 2
    group by
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        u.Reputation
),
FilteredQuestions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        p.AcceptedAnswerId,
        array_agg(distinct regexp_split_to_array(trim(both '<>' from p.Tags), '><'))[1:3] as Top3Tags,
        (
            select count(distinct pl.RelatedPostId)
            from PostLinks pl
            where pl.PostId = p.Id
              and pl.LinkTypeId = 1
        ) as LinkedCount,
        lhs.RemoveFlagCloseCount,
        coalesce(al.MaxAnswerReputation, 0) as MaxAnswerReputation,
        ROW_NUMBER() OVER (PARTITION BY date_trunc('month', p.CreationDate) ORDER BY p.Score DESC) as MonthlyRankForScore
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
        left join (
            select
                PostId,
                count(case when PostHistoryTypeId = 10 then 1 end) as RemoveFlagCloseCount
            from
                PostHistory
            where
                PostHistoryTypeId in (10,12) -- closed or deleted close votes
            group by PostId
        ) lhs on lhs.PostId = p.Id
        left join (
            select
                a.ParentId,
                max(u.Reputation) as MaxAnswerReputation
            from
                Posts a
                left join Users u on a.OwnerUserId = u.Id
            where
                a.PostTypeId = 2
            group by
                a.ParentId
        ) al on al.ParentId = p.Id
    where
        p.PostTypeId = 1
        and p.Score > 0
        and (acessing := p.AcceptedAnswerId is null or exists(select 1 from Posts ax where ax.Id = p.AcceptedAnswerId))
    group by
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        p.AcceptedAnswerId,
        lhs.RemoveFlagCloseCount,
        al.MaxAnswerReputation,
        p.CreationDate
),
CorrelatedBadgeCount as (
    select
        b.UserId,
        b.Name,
        dense_rank() over (partition by b.UserId order by b.Date desc) as RecentBadgeRank
    from Badges b
    where b.Class in (1,2)
),
UserBadgesFilter as (
    select
        UserId,
        count(*) filter (where RecentBadgeRank = 1) as RecentBadges,
        count(*) filter (where Name ilike '%gold%') as GoldBadges,
        count(*) filter (where Name ilike '%silver%') as SilverBadges,
        count(*) filter (where Name ilike '%bronze%') as BronzeBadges
    from
        CorrelatedBadgeCount
    group by
        UserId
),
EnhancedQuestions as (
    select 
        fq.*,
        ub.RecentBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        case 
            when fq.Score > 100 then 'Hot' 
            when fq.Score > 50 then 'Trending' 
            else 'Normal' 
        end as PopularityFlag,
        fq.ViewCount / nullif(fq.Score,1) + 0.1 * coalesce(fq.RemoveFlagCloseCount,0) as AdjustedViewToScoreRatio
    from
        FilteredQuestions fq
        left join UserBadgesFilter ub on ub.UserId = fq.OwnerUserId
),
ExplanationComments AS (
    select
        ch.Id,
        ch.PostId,
        ch.Score,
        ch.Text,
        ch.CreationDate,
        ch.UserDisplayName,
        ch.UserId,
        ranking() over (partition by ch.PostId order by ch.Score desc, ch.CreationDate asc) as CommentRank
    from
        Comments ch
    where
        ch.Text ilike '%explain%'
        or ch.Text ilike '%clarify%'
),
PostsWithCloseReasons as (
    select
        ph.PostId,
        string_agg(distinct crt.Name, ', ') as CloseReasonsAggregated
    from
        PostHistory ph
        left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where
        ph.PostHistoryTypeId = 10
    group by
        ph.PostId
)
select distinct
    eq.Id,
    eq.Title,
    string_agg(RTRIM(TagName), ', ') within group (order by RTRIM(TagName) asc) as TagsSample,
    eq.Score,
    eq.ViewCount,
    eq.AcceptedAnswerId,
    coalesce(eq.MaxAnswerReputation, 0) as MaxAnswerReputation,
    ebuf.RecentBadges,
    ebuf.GoldBadges,
    ebuf.SilverBadges,
    ebuf.BronzeBadges,
    eq.PopularityFlag,
    eq.AdjustedViewToScoreRatio,
    coalesce(pwr.CloseReasonsAggregated, 'None') as CloseReasons,
    cex.Id as CommentId,
    cex.UserDisplayName as CommentAuthor,
    left(cex.Text, 60) as CommentExcerpt
from
    EnhancedQuestions eq
    left join PostsWithCloseReasons pwr on eq.Id = pwr.PostId
    left join ExplanationComments cex on cex.PostId = eq.Id and cex.CommentRank = 1
    left join UserBadgesFilter ebuf on ebuf.UserId = eq.OwnerUserId
where
    eq.MonthlyRankForScore <= 15
order by
    eq.Score desc,
    eq.ViewCount desc,
    eq.Id
limit 50;