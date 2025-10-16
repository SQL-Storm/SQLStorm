-- {"query": "1208.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1382} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        parent.Id as ParentTagId,
        1 as Depth,
        array[t.TagName] as Path
    from Tags t
    left join PostLinks pl on pl.PostId = t.ExcerptPostId and pl.LinkTypeId = 1
    left join Tags parent on parent.ExcerptPostId = pl.RelatedPostId
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        th.Id,
        th.TagName,
        th.Count,
        parent.Id as ParentTagId,
        rth.Depth + 1 as Depth,
        rth.Path || parent.TagName
    from RecursiveTagHierarchy rth
    join PostLinks pl on pl.PostId = rth.ExcerptPostId and pl.LinkTypeId = 1
    join Tags parent on parent.ExcerptPostId = pl.RelatedPostId
    where not parent.TagName = any(rth.Path)
), 
UserScoreStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(vs.TotalScore),0) score_sum,
        percentile_cont(0.5) within group(order by vs.AvgAnswerScore) as MedianAnswerScore
    from Users u
    left join Badges b on b.UserId = u.Id
    left join lateral (
        select 
            p.OwnerUserId,
            avg(p.Score) as AvgAnswerScore,
            sum(p.Score) as TotalScore
        from Posts p
        where p.PostTypeId = 2 and p.OwnerUserId = u.Id
        group by p.OwnerUserId
    ) vs on vs.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), 
PostAndComments as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.ParentId,
        p.Tags,
        p.Title,
        c.CommentCount,
        c.TotalCommentScore,
        c.UniqueCommenters
    from Posts p
    left join (
        select 
            PostId,
            count(*) as CommentCount,
            sum(coalesce(Score,0)) as TotalCommentScore,
            count(distinct UserId) as UniqueCommenters
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
), 
RankedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
), 
PostRelations as (
    select distinct
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
), 
CloseReasonCounts as (
    select
        p.Id as PostId,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes,
        max(case when ph.PostHistoryTypeId=10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id
)

select distinct
    u.Id as UserId, u.DisplayName, u.Reputation, u.GoldBadges, u.SilverBadges, u.BronzeBadges,
    us.score_sum,
    us.MedianAnswerScore,
    p.Id as PostId, p.PostTypeId, p.CreationDate, p.Score as PostScore, p.ViewCount, p.Title,
    p.CommentCount, p.TotalCommentScore, p.UniqueCommenters,
    ra.AnswerRank,
    pr.RelatedPostId, pr.LinkTypeName,
    crt.CloseVotes, crt.ReopenVotes, crt.CloseReasonId,
    array_to_string(rth.Path, ' > ') as TagHierarchyPath,
    -- Complex calculation including string expressions and NULL logic
    (
       case 
         when p.PostTypeId = 1 then 
          greatest(0, p.Score) * coalesce(p.ViewCount,0) 
          + (select count(*) from PostLinks pl2 where pl2.PostId = p.Id and LinkTypeId = 1)
          + length(coalesce(p.Tags, '')) / 10
       else 
         coalesce(p.Score,0) * (select count(*) from Comments c2 where c2.PostId = p.Id)
       end
    ) +
    (
      case when crt.CloseReasonId is not null then 
        case crt.CloseReasonId 
           when 101 then 50
           when 102 then 20
           when 103 then 10
           when 104 then 5
           when 105 then 1
           else 0
        end
      else 0 end
    ) as ComputedMetric
from Users u
inner join UserScoreStats us on us.Id = u.Id
inner join Posts p on p.OwnerUserId = u.Id and p.Score > 0 and p.CreationDate > current_date - interval '365 days'
left join RankedAnswers ra on ra.Id = p.Id
left join PostRelations pr on pr.PostId = p.Id
left join CloseReasonCounts crt on crt.PostId = p.Id
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(p.Tags,''),'><'))
where u.Reputation > 1000
and ( 
    exists (
      select 1 from Posts pa 
      where pa.ParentId = p.Id and pa.Score > 5 and pa.CreationDate > current_date - interval '180 days'
    )
    or 
    coalesce(p.CommentCount,0) > 3
)
order by us.score_sum desc, ComputedMetric desc, p.Score desc
limit 100;