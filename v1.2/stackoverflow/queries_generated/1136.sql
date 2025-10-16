-- {"query": "1136.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1684} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        coalesce(p.ParentId, -1) as ParentTagPostId,
        1 as Level,
        array[t.TagName] as AncestorTags
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        rth.Id,
        rth.TagName,
        coalesce(p2.ParentId, -1),
        rth.Level + 1,
        AncestorTags || rth.TagName
    from RecursiveTagHierarchy rth
    join Posts p2 on p2.Id = rth.ParentTagPostId and p2.PostTypeId = 1
    where rth.Level < 3
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(bingold.GoldCount,0) as GoldBadges,
        coalesce(bingsilver.SilverCount,0) as SilverBadges,
        coalesce(binbronze.BronzeCount,0) as BronzeBadges,
        upstream.UpVoteCount,
        downstream.DownVoteCount,
        case when u.LastAccessDate > current_timestamp - interval '30 days' then 1 else 0 end as IsActiveUser
    from Users u
    left join (
        select UserId, count(*) as GoldCount from Badges where Class=1 group by UserId
    ) bingold on u.Id = bingold.UserId
    left join (
        select UserId, count(*) as SilverCount from Badges where Class=2 group by UserId
    ) bingsilver on u.Id = bingsilver.UserId
    left join (
        select UserId, count(*) as BronzeCount from Badges where Class=3 group by UserId
    ) binbronze on u.Id = binbronze.UserId
    left join (
        select UserId, count(*) as UpVoteCount from Votes v
        join Posts p on p.Id = v.PostId
        where v.VoteTypeId = 2 and p.OwnerUserId is not null
        group by UserId
    ) upstream on u.Id = upstream.UserId
    left join (
        select UserId, count(*) as DownVoteCount from Votes v
        join Posts p on p.Id = v.PostId
        where v.VoteTypeId = 3 and p.OwnerUserId is not null
        group by UserId
    ) downstream on u.Id = downstream.UserId
),
QuestionStats as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select max(ph.CreationDate) from PostHistory ph where ph.PostId = p.Id and ph.PostHistoryTypeId in (10,11)) as CloseReopenDate,
        p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId = 1
),
AnswersWithRanks as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankByScore,
        dense_rank() over (partition by a.ParentId order by a.CreationDate desc) as RankByRecency
    from Posts a
    where a.PostTypeId = 2
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
FilteredQuestions as (
    select 
        qs.*,
        pls.LinkedCount,
        pls.DuplicateCount,
        ua.Reputation as OwnerRep,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.UpVoteCount,
        ua.DownVoteCount,
        ua.IsActiveUser,
        -- Extract first tag name
        substring(qs.Tags from '<([^>]+)>') as FirstTag
    from QuestionStats qs
    left join PostLinkSummary pls on qs.Id = pls.PostId
    left join UserAggregates ua on qs.OwnerUserId = ua.Id
    where qs.ViewCount > 1000 and qs.AnswerCount > 0 and ua.Reputation > 100
)
select 
    fq.Id as QuestionId,
    fq.Title,
    fq.FirstTag,
    fq.ViewCount,
    fq.Score,
    fq.AnswerCount,
    fq.FavoriteCount,
    fq.CommentCount,
    fq.LinkedCount,
    fq.DuplicateCount,
    fq.OwnerRep,
    fq.GoldBadges,
    fq.SilverBadges,
    fq.BronzeBadges,
    fq.UpVoteCount,
    fq.DownVoteCount,
    fq.IsActiveUser,
    coalesce(fq.CloseReopenDate, timestamp '9999-12-31') as LastCloseReopenDate,
    array_agg(distinct rth.AncestorTags order by rth.Level) filter (where rth.Id is not null) as TagHierarchies,
    -- Nest answers ranked by score and recency
    (
        select json_agg(json_build_object(
            'AnswerId', awr.Id,
            'Score', awr.Score,
            'RankByScore', awr.RankByScore,
            'RankByRecency', awr.RankByRecency,
            'OwnerUserId', awr.OwnerUserId,
            'OwnerReputation', ua2.Reputation,
            'OwnerGoldBadges', coalesce(b1.GoldCount,0),
            'OwnerSilverBadges', coalesce(b2.SilverCount,0),
            'OwnerBronzeBadges', coalesce(b3.BronzeCount,0)
        ) order by awr.RankByScore ASC )
        from AnswersWithRanks awr
        left join UserAggregates ua2 on awr.OwnerUserId = ua2.Id
        left join (
            select UserId, count(*) as GoldCount from Badges where Class=1 group by UserId
        ) b1 on awr.OwnerUserId = b1.UserId
        left join (
            select UserId, count(*) as SilverCount from Badges where Class=2 group by UserId
        ) b2 on awr.OwnerUserId = b2.UserId
        left join (
            select UserId, count(*) as BronzeCount from Badges where Class=3 group by UserId
        ) b3 on awr.OwnerUserId = b3.UserId
        where awr.ParentId = fq.Id
    ) as AnswersDetail,
    -- Count of distinct users commenting on the question
    (select count(distinct c.UserId) from Comments c where c.PostId = fq.Id and c.UserId is not null) as DistinctCommenters,
    -- Weighted Score calculation example (Score + 0.1 * Views + 2*FavoriteCount - 0.5 * DownVotes)
    (fq.Score + 0.1 * fq.ViewCount + 2 * fq.FavoriteCount - 0.5 * fq.DownVoteCount) as WeightedScore
from FilteredQuestions fq
left join RecursiveTagHierarchy rth on fq.FirstTag = rth.TagName
order by WeightedScore desc
limit 20;