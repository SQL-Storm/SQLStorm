-- {"query": "115.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1521} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2)::int as UpVotes,
        sum(v.VoteTypeId = 3)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        u.DisplayName as OwnerName,
        p.Title as RelatedTitle
    from PostLinks pl
    join Posts p on p.Id = pl.RelatedPostId
    left join Users u on u.Id = p.OwnerUserId
    where pl.LinkTypeId = 3 -- Duplicate
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.VoteTypeId = 2)::int, 0) as TotalUpVotes,
        coalesce(sum(v.VoteTypeId = 3)::int, 0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopTagsWithQuestions as (
    select
        rtc.TagName,
        rtc.Count,
        rtc.AnswerCount,
        rtc.ViewCount,
        rtc.Score,
        (select count(*) from Posts p where p.PostTypeId = 1 and p.Tags like concat('%<', rtc.TagName, '>%')) as QuestionCount,
        (select avg(p.Score) from Posts p where p.PostTypeId = 1 and p.Tags like concat('%<', rtc.TagName, '>%')) as AvgQuestionScore
    from RecursiveTagCounts rtc
    where rtc.TagRank <= 50
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.CommentsMade,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    coalesce(cq.CloseDate, timestamp '1970-01-01') as LastClosedQuestionDate,
    coalesce(dl.RelatedPostId, -1) as DuplicateOfPostId,
    dl.RelatedPostId is not null as HasDuplicates,
    ptw.TagName as PopularTag,
    ptw.QuestionCount,
    ptw.AvgQuestionScore,
    paw.Score as RecentPostScore,
    paw.PrevScore,
    paw.NextScore,
    case
        when paw.Score is null then 'No recent posts'
        when paw.Score > coalesce(paw.PrevScore, 0) and paw.Score > coalesce(paw.NextScore, 0) then 'Local Max Score'
        when paw.Score < coalesce(paw.PrevScore, 0) and paw.Score < coalesce(paw.NextScore, 0) then 'Local Min Score'
        else 'Normal'
    end as PostScoreTrend
from Users u
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join UserActivitySummary uas on uas.Id = u.Id
left join ClosedQuestions cq on cq.PostId = (select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by cq.CreationDate desc limit 1)
left join DuplicateLinks dl on dl.PostId = (select p.Id from Posts p where p.OwnerUserId = u.Id order by p.CreationDate desc limit 1)
left join TopTagsWithQuestions ptw on ptw.TagName = (
    select unnest(string_to_array(coalesce((select Tags from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by CreationDate desc limit 1), ''), '><'))
    limit 1
)
left join PostActivityWindow paw on paw.OwnerUserId = u.Id and paw.RecentPostRank = 1
where u.Reputation > 1000
order by u.Reputation desc, uas.QuestionsAsked desc
limit 100;