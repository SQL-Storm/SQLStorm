-- {"query": "2413.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1743} 
with RecursiveCTE as (
    select 
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        1 as Depth,
        cast(p.Id as varchar) as Path
    from Posts p
    where p.ParentId is null and p.PostTypeId = 1

    union all

    select 
        c.Id,
        c.PostTypeId,
        c.AcceptedAnswerId,
        c.ParentId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.Title,
        c.Tags,
        r.Depth + 1,
        r.Path || '>' || cast(c.Id as varchar)
    from Posts c
    inner join RecursiveCTE r on c.ParentId = r.Id
    where c.PostTypeId = 2
),
BadgeRankings as (
    select 
        UserId,
        Name,
        Class,
        rank() over (partition by UserId order by Class asc, Date desc) as BadgeRank
    from Badges
    where TagBased = 0
),
UserEngagement as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct b.Id) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        coalesce(sum(vtCounts.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vtCounts.DownVotes),0) as TotalDownVotes,
        coalesce(avg(pc.AvgPostScore),0) as AveragePostScore,
        count(distinct c.Id) as TotalComments
    from Users u
    left join Badges b on b.UserId = u.Id and b.TagBased = 0
    left join (
        select 
            p.OwnerUserId,
            avg(p.Score) as AvgPostScore
        from Posts p
        group by p.OwnerUserId
    ) pc on pc.OwnerUserId = u.Id
    left join (
        select 
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p 
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vtCounts on vtCounts.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
PostActivitySummary as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        coalesce(phc.CloseCount,0) as CloseVotes,
        coalesce(phr.ReopenCount,0) as ReopenVotes,
        coalesce(phu.UndeleteCount,0) as UndeleteCount,
        coalesce(vtUp.UpVotes,0) as UpVotes,
        coalesce(vtDown.DownVotes,0) as DownVotes,
        coalesce(cmt.CommentCount,0) as CommentCount
    from Posts p
    left join (
        select PostId, count(*) as CloseCount from PostHistory 
        where PostHistoryTypeId = 10
        group by PostId
    ) phc on phc.PostId = p.Id
    left join (
        select PostId, count(*) as ReopenCount from PostHistory 
        where PostHistoryTypeId = 11
        group by PostId
    ) phr on phr.PostId = p.Id
    left join (
        select PostId, count(*) as UndeleteCount from PostHistory 
        where PostHistoryTypeId = 13
        group by PostId
    ) phu on phu.PostId = p.Id
    left join (
        select PostId, sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes from Votes 
        group by PostId
    ) vtUp on vtUp.PostId = p.Id
    left join (
        select PostId, sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes from Votes 
        group by PostId
    ) vtDown on vtDown.PostId = p.Id
    left join (
        select PostId, count(*) as CommentCount from Comments 
        group by PostId
    ) cmt on cmt.PostId = p.Id
),
RankedPosts as (
    select 
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        row_number() over (
            partition by p.OwnerUserId 
            order by p.Score desc, p.ViewCount desc, p.CreationDate desc
        ) as UserPostRank
    from Posts p
    where p.PostTypeId = 1
),
FilteredQuestions as (
    select * from RankedPosts
    where UserPostRank <= 3
),
CorrelatedCTE as (
    select
        fq.Id,
        fq.Title,
        fq.OwnerUserId,
        fq.Score,
        fq.ViewCount,
        fq.CreationDate,
        fq.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        (select count(*) from Posts a where a.ParentId = fq.Id) as AnswerCount,
        (select avg(a.Score) from Posts a where a.ParentId = fq.Id) as AvgAnswerScore,
        (select max(c.Score) from Comments c where c.PostId = fq.Id) as MaxCommentScore,
        (select count(*) from DuplicateLinks dl where dl.PostId = fq.Id or dl.RelatedPostId = fq.Id) as DuplicateRelations
    from FilteredQuestions fq
    left join Users u on u.Id = fq.OwnerUserId
)
select
    c.Id,
    c.Title,
    c.OwnerName,
    ueg.TotalBadges,
    ueg.GoldBadges,
    ueg.SilverBadges,
    ueg.BronzeBadges,
    c.Score,
    c.ViewCount,
    c.AnswerCount,
    round(coalesce(c.AvgAnswerScore,0),2) as AvgAnswerScore,
    coalesce(c.MaxCommentScore,0) as MaxCommentScore,
    c.DuplicateRelations,
    pa.CloseVotes,
    pa.ReopenVotes,
    pa.UndeleteCount,
    pa.UpVotes,
    pa.DownVotes,
    pa.CommentCount,
    case 
        when c.Score < 0 then 'Negative'
        when c.Score = 0 then 'Neutral'
        when c.Score > 0 and c.Score <= 10 then 'Low Positive'
        else 'High Positive'
    end as ScoreCategory,
    case 
        when pos.RuleCount = 0 then 'No PostHistory'
        else 'Has PostHistory'
    end as PostHistoryStatus,
    rct.Depth,
    rct.Path,
    dense_rank() over (order by c.ViewCount desc) as ViewRank
from CorrelatedCTE c
left join UserEngagement ueg on ueg.Id = c.OwnerUserId
left join PostActivitySummary pa on pa.PostId = c.Id
left join (
    select PostId, count(*) as RuleCount from PostHistory group by PostId
) pos on pos.PostId = c.Id
left join RecursiveCTE rct on rct.Id = c.Id
where c.DuplicateRelations > 0
order by c.ViewCount desc, c.Score desc
limit 100;