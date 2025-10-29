-- {"query": "2509.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1270}
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        p.Id as PostId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        row_number() over(partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%' and p.PostTypeId = 1
    left join Users u on p.OwnerUserId = u.Id
    where t.IsRequired = false and p.ClosedDate is null
),
FilteredPosts as (
    select
        rth.TagName,
        rth.PostId,
        rth.CreationDate,
        rth.Score,
        rth.ViewCount,
        rth.OwnerName,
        rth.OwnerReputation,
        coalesce(ph_vote.SumUpVotes, 0) as TotalUpVotes,
        coalesce(ph_vote.SumDownVotes, 0) as TotalDownVotes,
        coalesce(bd.GoldBadges, 0) as GoldBadges,
        coalesce(bd.SilverBadges, 0) as SilverBadges,
        coalesce(bd.BronzeBadges, 0) as BronzeBadges,
        (CASE 
          WHEN rth.Score > 50 THEN 'High'
          WHEN rth.Score BETWEEN 20 AND 50 THEN 'Medium'
          ELSE 'Low' 
        END) as ScoreCategory,
        dense_rank() over(partition by rth.TagName order by rth.Score desc) as RankWithinTag
    from RecursiveTagHierarchy rth
    left join (
        select 
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as SumUpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as SumDownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.PostId
    ) ph_vote on rth.PostId = ph_vote.PostId
    left join (
        select
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) bd on bd.UserId = (
        select Id from Users where DisplayName = rth.OwnerName fetch first 1 row only
    )
    where rth.rn <= 100
),
CorrelatedActivity as (
    select
        p.Id as PostId,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate > p.CreationDate) as CommentsAfterCreation,
        (select max(p2.Score) from Posts p2 where p2.ParentId = p.Id) as MaxAnswerScore,
        (select count(distinct pl.RelatedPostId) from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 1) as LinkedCount,
        (select count(distinct pl.RelatedPostId) from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 3) as DuplicateCount
    from Posts p
    where p.PostTypeId = 1
),
FinalStats as (
    select
        fp.TagName,
        fp.PostId,
        fp.CreationDate,
        fp.Score,
        fp.ViewCount,
        fp.OwnerName,
        fp.OwnerReputation,
        fp.TotalUpVotes,
        fp.TotalDownVotes,
        fp.GoldBadges,
        fp.SilverBadges,
        fp.BronzeBadges,
        fp.ScoreCategory,
        fp.RankWithinTag,
        ca.CommentsAfterCreation,
        ca.MaxAnswerScore,
        ca.LinkedCount,
        ca.DuplicateCount,
        case when fp.TotalUpVotes > fp.TotalDownVotes then 'NetPositive' else 'NetNegativeOrZero' end as VoteBalance,
        (lower(fp.ScoreCategory) || ' | ' || coalesce(fp.OwnerName, '') || ' | ' || cast(fp.OwnerReputation as varchar) || ' | ' || coalesce(cast(ca.MaxAnswerScore as varchar), '0')) as CompositeKey
    from FilteredPosts fp
    left join CorrelatedActivity ca on fp.PostId = ca.PostId
),
RankedResults as (
    select
        fs.TagName,
        fs.PostId,
        fs.CreationDate,
        fs.Score,
        fs.ViewCount,
        fs.OwnerName,
        fs.OwnerReputation,
        fs.TotalUpVotes,
        fs.TotalDownVotes,
        fs.GoldBadges,
        fs.SilverBadges,
        fs.BronzeBadges,
        fs.ScoreCategory,
        fs.RankWithinTag,
        fs.CommentsAfterCreation,
        fs.MaxAnswerScore,
        fs.LinkedCount,
        fs.DuplicateCount,
        fs.VoteBalance,
        fs.CompositeKey,
        rank() over(partition by fs.TagName order by fs.Score desc, fs.TotalUpVotes desc) as OverallRank
    from FinalStats fs
),
ComplexStringFilter as (
    select *
    from RankedResults
    where lower(CompositeKey) like '%high%'
      and VoteBalance = 'NetPositive'
      and (GoldBadges + SilverBadges + BronzeBadges) > 5
      and (CommentsAfterCreation is null or CommentsAfterCreation > 3)
),
UnionResults as (
    select TagName, PostId, OwnerName, Score, ViewCount, CompositeKey, 'Qualified' as Status
    from ComplexStringFilter
    union
    select TagName, PostId, OwnerName, Score, ViewCount, CompositeKey, 'Others' as Status
    from RankedResults
    where PostId not in (select PostId from ComplexStringFilter)
)
select 
    TagName,
    PostId,
    OwnerName,
    Score,
    ViewCount,
    Status,
    CompositeKey,
    count(*) over (partition by TagName order by Score desc) as CumulativeCount,
    lag(Score) over (partition by TagName order by Score desc) as PrevScore,
    lead(Score) over (partition by TagName order by Score desc) as NextScore
from UnionResults
order by TagName, Score desc, PostId
fetch first 200 rows only;