-- {"query": "178.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1581} 
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
        p.AcceptedAnswerId,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2)::int as UpVotes,
        sum(v.VoteTypeId = 3)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title, p.AcceptedAnswerId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
    where pl.LinkTypeId = 3 -- Duplicate
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        extract(epoch from (max(p.CreationDate) - min(p.CreationDate))) / 86400 as ActiveDays
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
AnswerScoreStats as (
    select
        QuestionId,
        count(AnswerId) as AnswerCount,
        max(AnswerScore) as MaxAnswerScore,
        avg(AnswerScore) as AvgAnswerScore,
        sum(case when AnswerScore > 10 then 1 else 0 end) as HighScoreAnswers
    from TopQuestionsWithAnswers
    group by QuestionId
)
select
    q.QuestionId,
    q.Title,
    q.QuestionDate,
    q.QuestionScore,
    q.ViewCount,
    q.Tags,
    coalesce(a.AnswerCount, 0) as TotalAnswers,
    coalesce(a.MaxAnswerScore, 0) as HighestAnswerScore,
    coalesce(a.AvgAnswerScore, 0)::numeric(10,2) as AverageAnswerScore,
    coalesce(a.HighScoreAnswers, 0) as AnswersAbove10Score,
    us.QuestionsAsked,
    us.AnswersGiven,
    us.CommentsMade,
    us.UpVotesGiven,
    us.DownVotesGiven,
    us.ActiveDays,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    cl.CloseDate,
    cl.CloseReason,
    cl.ClosedByUserName,
    dl.LinkCreator as DuplicateLinkCreator,
    dl.CreationDate as DuplicateLinkDate
from TopQuestionsWithAnswers q
left join AnswerScoreStats a on a.QuestionId = q.QuestionId
left join Users u on u.Id = (select OwnerUserId from Posts where Id = q.QuestionId)
left join UserActivitySummary us on us.Id = u.Id
left join UserBadgeStats ub on ub.UserId = u.Id
left join ClosedQuestions cl on cl.PostId = q.QuestionId
left join DuplicateLinks dl on dl.PostId = q.QuestionId
where q.AnswerRank = 1 or q.AnswerRank is null
and (q.QuestionScore > 5 or coalesce(a.MaxAnswerScore, 0) > 10)
order by q.QuestionScore desc nulls last, a.MaxAnswerScore desc nulls last, q.QuestionDate desc
limit 100;