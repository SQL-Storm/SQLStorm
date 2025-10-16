-- {"query": "822.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1468} 
with RecursiveUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        coalesce(avg(p.Score), 0) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
UserActivityWindow as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.BadgeCount,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.AvgPostScore,
        u.MaxPostScore,
        u.ReputationRank,
        count(distinct ph.Id) filter (where ph.CreationDate >= u.CreationDate and ph.CreationDate < u.CreationDate + interval '30 day') as EditsFirst30Days,
        count(distinct c.Id) filter (where c.CreationDate >= u.CreationDate and c.CreationDate < u.CreationDate + interval '30 day') as CommentsFirst30Days,
        count(distinct v.Id) filter (where v.CreationDate >= u.CreationDate and v.CreationDate < u.CreationDate + interval '30 day') as VotesFirst30Days
    from RecursiveUserStats u
    left join PostHistory ph on ph.UserId = u.UserId
    left join Comments c on c.UserId = u.UserId
    left join Votes v on v.UserId = u.UserId
    group by u.UserId, u.DisplayName, u.Reputation, u.Location, u.BadgeCount, u.GoldBadges, u.SilverBadges, u.BronzeBadges, u.AvgPostScore, u.MaxPostScore, u.ReputationRank, u.CreationDate
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by t.Count desc) as TagRank
    from Tags t
    inner join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    where p.PostTypeId = 1
),
TopUserTags as (
    select
        OwnerUserId as UserId,
        string_agg(TagName, ',' order by TagRank) as UserTopTags
    from TopTags
    where TagRank <= 3
    group by OwnerUserId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwnerId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(acc.Score,0) as AcceptedAnswerScore,
        coalesce(avgans.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(maxans.MaxAnswerScore,0) as MaxAnswerScore
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on ans.ParentId = q.Id
    left join Posts acc on acc.Id = q.AcceptedAnswerId
    left join (
        select ParentId, avg(Score) as AvgAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) avgans on avgans.ParentId = q.Id
    left join (
        select ParentId, max(Score) as MaxAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) maxans on maxans.ParentId = q.Id
    where q.PostTypeId = 1
),
DuplicateQuestionLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p.Title as RelatedTitle,
        p.Score as RelatedScore
    from PostLinks pl
    inner join Posts p on p.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        ph.UserId as CloseVoterId
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.BadgeCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.AvgPostScore,
    ua.MaxPostScore,
    ua.ReputationRank,
    ua.EditsFirst30Days,
    ua.CommentsFirst30Days,
    ua.VotesFirst30Days,
    tut.UserTopTags,
    qs.QuestionId,
    qs.Title as QuestionTitle,
    qs.QuestionCreationDate,
    qs.QuestionScore,
    qs.QuestionViews,
    qs.AnswerCount,
    qs.AcceptedAnswerScore,
    qs.AvgAnswerScore,
    qs.MaxAnswerScore,
    dq.RelatedPostId as DuplicateOfQuestionId,
    dq.RelatedTitle as DuplicateOfQuestionTitle,
    dq.RelatedScore as DuplicateOfQuestionScore,
    cqwr.CloseReasonName,
    cqwr.CloseDate,
    cqwr.CloseVoterId
from UserActivityWindow ua
left join TopUserTags tut on tut.UserId = ua.UserId
left join QuestionAnswerStats qs on qs.QuestionOwnerId = ua.UserId
left join DuplicateQuestionLinks dq on dq.PostId = qs.QuestionId
left join ClosedQuestionsWithReasons cqwr on cqwr.PostId = qs.QuestionId
where ua.Reputation > 1000
  and (ua.GoldBadges > 0 or ua.SilverBadges > 5)
  and qs.QuestionScore > 5
  and (dq.RelatedPostId is not null or cqwr.CloseReasonName is not null)
order by ua.ReputationRank, qs.QuestionScore desc
limit 100;