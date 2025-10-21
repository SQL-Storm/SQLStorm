-- {"query": "4057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1944} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        0 as Depth,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        rh.Depth + 1,
        rh.Path || ' > ' || child.TagName
    from Tags child
    inner join RecursiveTagHierarchy rh on child.Id > rh.Id and child.IsModeratorOnly = 0 and child.IsRequired = 0
    where rh.Depth < 2
),
RecentHighRepUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    where u.Reputation >= 5000 and u.CreationDate >= now() - interval '2 years'
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostEngagement as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CreationDate,
        coalesce(phc.CloseCount, 0) as CloseVotesCount,
        coalesce(vu.UpVotes, 0) as UpVotes,
        coalesce(vd.DownVotes, 0) as DownVotes,
        round(coalesce(p.Score, 0) * 1.0 / nullif(p.ViewCount, 0), 6) as ScorePerView,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts p
    left join (
        select
            ph.PostId,
            count(*) as CloseCount
        from PostHistory ph
        where ph.PostHistoryTypeId = 10 /* Post Closed */
        group by ph.PostId
    ) phc on p.Id = phc.PostId
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.PostId
    ) vu on p.Id = vu.PostId
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.PostId
    ) vd on p.Id = vd.PostId
),
PostLinkedDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
ComplexUserSummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        coalesce(badgs.GoldBadges, 0) as GoldBadges,
        coalesce(badgs.SilverBadges, 0) as SilverBadges,
        coalesce(badgs.BronzeBadges, 0) as BronzeBadges,
        coalesce(badgs.TotalBadges, 0) as TotalBadges,
        coalesce(pst.AnswerCount, 0) as TotalAnswers,
        coalesce(pst.QuestionCount, 0) as TotalQuestions,
        coalesce(avgScore.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(avgScore.AvgQuestionScore, 0) as AvgQuestionScore,
        row_number() over (partition by u.Location order by u.Reputation desc) as RegionalRank
    from Users u
    left join UserBadgeStats badgs on u.Id = badgs.UserId
    left join (
        select OwnerUserId,
            count(case when PostTypeId = 2 then 1 end) as AnswerCount,
            count(case when PostTypeId = 1 then 1 end) as QuestionCount
        from Posts
        group by OwnerUserId
    ) pst on u.Id = pst.OwnerUserId
    left join (
        select OwnerUserId,
            avg(case when PostTypeId = 2 then Score end) as AvgAnswerScore,
            avg(case when PostTypeId = 1 then Score end) as AvgQuestionScore
        from Posts
        group by OwnerUserId
    ) avgScore on u.Id = avgScore.OwnerUserId
    where u.Location is not null
),
AnswerDetailWithComments as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwner,
        q.OwnerUserId as QuestionOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        cmt.CommentCount,
        cmt.AvgCommentLength
    from Posts a
    join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    left join (
        select 
            c.PostId,
            count(c.Id) as CommentCount,
            avg(length(c.Text)) as AvgCommentLength
        from Comments c
        group by c.PostId
    ) cmt on a.Id = cmt.PostId
    where a.PostTypeId = 2
),
FinalResults as (
    select
        cu.UserId,
        cu.DisplayName,
        cu.Reputation,
        cu.Location,
        cu.GoldBadges,
        cu.SilverBadges,
        cu.BronzeBadges,
        cu.TotalBadges,
        cu.TotalAnswers,
        cu.TotalQuestions,
        cu.AvgAnswerScore,
        cu.AvgQuestionScore,
        rh.Path as SampleTagPath,
        pe.PostId,
        pe.Title,
        pe.Score,
        pe.ViewCount,
        pe.ScorePerView,
        pe.FavoriteCount,
        pe.AnswerCount,
        pe.HasAcceptedAnswer,
        coalesce(dup.DuplicateCount, 0) as DuplicateLinks,
        ad.CommentCount as AnswerComments,
        ad.AvgCommentLength
    from ComplexUserSummary cu
    join PostEngagement pe on cu.UserId = pe.OwnerUserId
    left join RecursiveTagHierarchy rh on rh.Depth = 0 and pe.Tags like '%' || rh.TagName || '%'
    left join PostLinkedDuplicates dup on dup.PostId = pe.PostId
    left join AnswerDetailWithComments ad on ad.AnswerId = pe.Id and pe.PostTypeId = 2
    where pe.PostTypeId in (1,2)
    and cu.TotalBadges >= 3
    and pe.CreationDate > now() - interval '5 years'
    and (pe.ClosedDate is null or pe.ClosedDate > now() - interval '1 year')
    order by cu.Reputation desc, pe.Score desc
    limit 100
)
select * from FinalResults
union
select
    cu.UserId,
    cu.DisplayName,
    cu.Reputation,
    cu.Location,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.TotalBadges,
    cu.TotalAnswers,
    cu.TotalQuestions,
    cu.AvgAnswerScore,
    cu.AvgQuestionScore,
    null as SampleTagPath,
    pe.PostId,
    pe.Title,
    pe.Score,
    pe.ViewCount,
    pe.ScorePerView,
    pe.FavoriteCount,
    pe.AnswerCount,
    pe.HasAcceptedAnswer,
    coalesce(dup.DuplicateCount, 0) as DuplicateLinks,
    null as AnswerComments,
    null as AvgCommentLength
from ComplexUserSummary cu
join PostEngagement pe on cu.UserId = pe.OwnerUserId
left join PostLinkedDuplicates dup on dup.PostId = pe.PostId
where pe.PostTypeId = 1
and cu.TotalBadges < 3
and pe.CreationDate > now() - interval '5 years'
and (pe.ClosedDate is null or pe.ClosedDate > now() - interval '1 year')
order by cu.Reputation asc, pe.Score asc
limit 50;