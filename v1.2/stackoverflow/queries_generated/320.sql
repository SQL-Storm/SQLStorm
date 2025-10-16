-- {"query": "320.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1399} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(b.Id) as TotalBadges,
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
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        p.OwnerUserId
    from PostHistory ph
    inner join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    inner join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
),
UserQuestionStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.ViewCount) filter (where p.PostTypeId = 1) as MaxQuestionViews,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) filter (where p.PostTypeId = 1) as QuestionsWithAcceptedAnswer
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
TopTagsWithQuestions as (
    select
        rtc.TagName,
        rtc.Count,
        count(distinct p.Id) as QuestionCount,
        sum(p.ViewCount) as TotalViews,
        avg(p.Score) as AvgScore,
        string_agg(distinct u.DisplayName, ', ') as TopAskers
    from RecursiveTagCounts rtc
    left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', rtc.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    group by rtc.TagName, rtc.Count
    having count(distinct p.Id) > 10
    order by rtc.Count desc
    limit 10
)
select
    uqs.UserId,
    uqs.DisplayName,
    uqs.QuestionCount,
    uqs.AnswerCount,
    uqs.AvgQuestionScore,
    uqs.AvgAnswerScore,
    uqs.MaxQuestionViews,
    uqs.QuestionsWithAcceptedAnswer,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    coalesce(ubs.TotalBadges, 0) as TotalBadges,
    max(cq.CloseDate) as LastClosedQuestionDate,
    count(distinct dq.PostId) as DuplicateLinksCount,
    string_agg(distinct tt.TagName, ', ') as TopTags
from UserQuestionStats uqs
left join UserBadgeSummary ubs on ubs.UserId = uqs.UserId
left join ClosedQuestions cq on cq.OwnerUserId = uqs.UserId
left join DuplicateLinks dq on dq.LinkCreator = uqs.DisplayName
left join TopTagsWithQuestions tt on tt.TopAskers like concat('%', uqs.DisplayName, '%')
where uqs.QuestionCount > 5
group by
    uqs.UserId,
    uqs.DisplayName,
    uqs.QuestionCount,
    uqs.AnswerCount,
    uqs.AvgQuestionScore,
    uqs.AvgAnswerScore,
    uqs.MaxQuestionViews,
    uqs.QuestionsWithAcceptedAnswer,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalBadges
order by TotalBadges desc, uqs.QuestionCount desc
limit 50;