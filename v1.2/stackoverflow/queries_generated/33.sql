-- {"query": "33.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1761} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (order by u.Reputation desc) as RepRank,
        avg(u.Reputation) over () as AvgReputation,
        max(u.Reputation) over () as MaxReputation
    from Users u
    where u.Reputation > 1000
),
PostAnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as AnswerCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        pas.AnswerCount,
        pas.TotalUpVotes,
        pas.TotalDownVotes,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        qcr.CloseReasonName,
        qcr.CloseDate,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation
    from Posts p
    left join PostAnswerStats pas on pas.QuestionId = p.Id
    left join QuestionCloseReasons qcr on qcr.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and p.Score > 10
      and (qcr.CloseDate is null or qcr.CloseDate > p.CreationDate)
),
RankedComments as (
    select
        c.PostId,
        c.Id as CommentId,
        c.Score,
        c.Text,
        c.CreationDate,
        c.UserId,
        row_number() over (partition by c.PostId order by c.Score desc, c.CreationDate asc) as CommentRank
    from Comments c
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.BadgeCount),0) as TotalBadges,
        coalesce(sum(case when vb.Class = 1 then vb.BadgeCount else 0 end),0) as GoldBadges,
        coalesce(sum(case when vb.Class = 2 then vb.BadgeCount else 0 end),0) as SilverBadges,
        coalesce(sum(case when vb.Class = 3 then vb.BadgeCount else 0 end),0) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join UserBadgeCounts vb on vb.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
CombinedQuestionsAndDuplicates as (
    select
        tq.Id,
        tq.Title,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        tq.Tags,
        tq.OwnerUserId,
        tq.AcceptedAnswerId,
        tq.AnswerCount,
        tq.TotalUpVotes,
        tq.TotalDownVotes,
        tq.AvgAnswerScore,
        tq.MaxAnswerScore,
        tq.CloseReasonName,
        tq.CloseDate,
        tq.OwnerName,
        tq.OwnerReputation,
        dl.RelatedPostId as DuplicateOf,
        dl.RelatedPostTitle as DuplicateOfTitle
    from TopQuestions tq
    left join DuplicateLinks dl on dl.PostId = tq.Id
)
select
    cqd.Id as QuestionId,
    cqd.Title,
    cqd.CreationDate,
    cqd.Score,
    cqd.ViewCount,
    coalesce(cqd.Tags, '') as Tags,
    cqd.OwnerUserId,
    cqd.OwnerName,
    cqd.OwnerReputation,
    cqd.AnswerCount,
    cqd.TotalUpVotes,
    cqd.TotalDownVotes,
    round(coalesce(cqd.AvgAnswerScore,0)::numeric,2) as AvgAnswerScore,
    cqd.MaxAnswerScore,
    cqd.CloseReasonName,
    cqd.CloseDate,
    cqd.DuplicateOf,
    cqd.DuplicateOfTitle,
    (select string_agg(distinct rth.Path, ' | ' order by rth.Level desc)
     from RecursiveTagHierarchy rth
     where position(rth.TagName in coalesce(cqd.Tags, '')) > 0
     limit 3) as TagHierarchyPaths,
    (select string_agg(distinct concat_ws(': ', ub.Name, ub.Class), ', ')
     from Badges ub
     where ub.UserId = cqd.OwnerUserId
     order by ub.Class, ub.Name
     limit 5) as OwnerTopBadges,
    (select rc.Text
     from RankedComments rc
     where rc.PostId = cqd.Id and rc.CommentRank = 1) as TopCommentText,
    (select count(*)
     from Votes v
     where v.PostId = cqd.Id and v.VoteTypeId = 2) as QuestionUpVotes,
    (select count(*)
     from Votes v
     where v.PostId = cqd.Id and v.VoteTypeId = 3) as QuestionDownVotes,
    (select count(*)
     from Votes v
     where v.PostId = cqd.AcceptedAnswerId and v.VoteTypeId = 2) as AcceptedAnswerUpVotes,
    (select count(*)
     from Votes v
     where v.PostId = cqd.AcceptedAnswerId and v.VoteTypeId = 3) as AcceptedAnswerDownVotes
from CombinedQuestionsAndDuplicates cqd
where cqd.OwnerReputation > (select avg(Reputation) from Users)
order by cqd.Score desc, cqd.ViewCount desc
limit 50;