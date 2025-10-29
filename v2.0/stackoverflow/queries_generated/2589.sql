-- {"query": "2589.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1338} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select t2.Id, t2.TagName, t2.Count, r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id > r.Id and not t2.Id = any(r.Path)
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0
    and array_length(r.Path,1) < 3
),
PostAggregates as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        cnt.AnswerCount,
        fav.FavoriteCount,
        coalesce(uv.UpVotes,0) - coalesce(dv.DownVotes,0) as NetVotes,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentTotal,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as RnkByUser,
        dense_rank() over (order by p.Score desc, p.ViewCount desc nulls last) as GlobalRank
    from Posts p
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) cnt on cnt.ParentId = p.Id and p.PostTypeId = 1
    left join (
        select PostId, count(*) as FavoriteCount
        from Posts
        group by PostId
    ) fav on fav.PostId = p.Id
    left join (
        select PostId, count(*) as UpVotes
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) uv on uv.PostId = p.Id
    left join (
        select PostId, count(*) as DownVotes
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) dv on dv.PostId = p.Id
    where p.PostTypeId in (1,2)
),
FilteredQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.NetVotes,
        p.CommentTotal,
        p.RnkByUser,
        p.GlobalRank,
        string_to_array(trim(both '<>' from p.Tags), '><') as TagArray
    from PostAggregates p
    where p.PostTypeId = 1
),
UserBadgeSummary as (
    select UserId,
           count(*) filter (where Class = 1) as GoldBadges,
           count(*) filter (where Class = 2) as SilverBadges,
           count(*) filter (where Class = 3) as BronzeBadges,
           count(distinct Name) as DistinctBadges
    from Badges
    group by UserId
),
TopCommenters as (
    select c.UserId, u.DisplayName, count(*) as CommentCount,
           row_number() over (order by count(*) desc) as CommentRank
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
    having count(*) > 10
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as TotalAnswers,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore,
        avg(p.Score) as AvgAnswerScore,
        sum(case when p.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
)
select
    fq.Id as QuestionId,
    fq.Title,
    fq.OwnerUserId,
    u.DisplayName as OwnerName,
    fq.CreationDate,
    fq.Score,
    fq.ViewCount,
    fq.AnswerCount,
    fq.FavoriteCount,
    fq.NetVotes,
    fq.CommentTotal,
    array_to_string(fq.TagArray, ',') as Tags,
    abs(fq.Score) * log(1 + fq.ViewCount) as PopularityIndex,
    coalesce(ab.GoldBadges,0) as GoldBadges,
    coalesce(ab.SilverBadges,0) as SilverBadges,
    coalesce(ab.BronzeBadges,0) as BronzeBadges,
    ab.DistinctBadges,
    coalesce(ans.TotalAnswers, 0) as TotalAnswers,
    coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(ans.MinAnswerScore, 0) as MinAnswerScore,
    coalesce(ans.AvgAnswerScore, 0) as AvgAnswerScore,
    coalesce(ans.AnonymousAnswers, 0) as AnonymousAnswers,
    tc.DisplayName as TopCommenterName,
    tc.CommentCount as TopCommenterComments,
    case
        when fq.ViewCount > 10000 and fq.AnswerCount > 5 then 'Hot Question'
        when fq.ViewCount between 1000 and 10000 then 'Popular Question'
        else 'Regular Question'
    end as PopularityCategory
from FilteredQuestions fq
left join Users u on u.Id = fq.OwnerUserId
left join UserBadgeSummary ab on ab.UserId = fq.OwnerUserId
left join AnswerStats ans on ans.QuestionId = fq.Id
left join lateral (
    select tc.DisplayName, tc.CommentCount
    from TopCommenters tc
    join Comments c2 on tc.UserId = c2.UserId and c2.PostId = fq.Id
    order by tc.CommentCount desc limit 1
) tc on true
where fq.GlobalRank <= 500
and exists (
    select 1
    from RecursiveTagHierarchy rth
    where rth.TagName = any(fq.TagArray)
    and rth.Id > 10
)
order by PopularityIndex desc, fq.ViewCount desc, fq.Score desc
limit 100;