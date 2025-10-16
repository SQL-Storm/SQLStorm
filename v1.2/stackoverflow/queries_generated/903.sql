-- {"query": "903.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1675} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        array[t.TagName] as TagPath
    from Tags t
    where t.IsRequired = 1

    union all

    select 
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    from Tags t
    join RecursiveTagHierarchy r
        on position(t.TagName in array_to_string(r.TagPath, ',')) = 0 -- avoid cycles
    where t.IsRequired = 1
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopQuestionsWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        count(a.Id) as AnswerCount,
        max(a.Score) filter (where a.Score is not null) as MaxAnswerScore,
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionComments,
        (select count(*) from Comments c where c.PostId in (select a2.Id from Posts a2 where a2.ParentId = q.Id)) as AnswerComments,
        string_agg(distinct ph.Comment, ' ||| ') filter (where ph.Comment is not null) as CloseReasons,
        lag(q.Score) over (order by q.CreationDate) as PreviousQuestionScore,
        lead(q.Score) over (order by q.CreationDate) as NextQuestionScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, u.DisplayName, u.Reputation
    having count(a.Id) > 0
    order by q.Score desc
    limit 100
),
UserActivityWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostsRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(p.Id) > 0
),
UserTopTags as (
    select 
        ua.Id as UserId,
        lower(trim(t.TagName)) as TagName,
        count(*) as TagUsageCount,
        rank() over (partition by ua.Id order by count(*) desc) as TagRank
    from Users ua
    join Posts p on p.OwnerUserId = ua.Id and p.PostTypeId = 1 and p.Tags is not null
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as t(TagName)
    group by ua.Id, t.TagName
    having count(*) > 2
),
ConsolidatedUserData as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.TotalPostScore,
        coalesce(uts.TagName, 'none') as TopTag,
        coalesce(uts.TagUsageCount, 0) as TagUsageCount,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.DistinctBadges,
        ubs.TagBasedBadges
    from UserActivityWindow ua
    left join UserTopTags uts on uts.UserId = ua.Id and uts.TagRank = 1
    left join UserBadgeStats ubs on ubs.UserId = ua.Id
    where ua.RecentPostsRank <= 5
)
select 
    tqa.QuestionId,
    tqa.Title,
    tqa.QuestionScore,
    tqa.ViewCount,
    tqa.OwnerName,
    tqa.OwnerReputation,
    tqa.AnswerCount,
    tqa.MaxAnswerScore,
    tqa.QuestionComments,
    tqa.AnswerComments,
    coalesce(tqa.CloseReasons, 'Open') as CloseReasons,
    cud.DisplayName as TopContributor,
    cud.Reputation as ContributorReputation,
    cud.TopTag as ContributorTopTag,
    cud.GoldBadges,
    cud.SilverBadges,
    cud.BronzeBadges,
    cud.DistinctBadges,
    cud.TagBasedBadges,
    rt.TagName as RecursiveTagName,
    rt.Count as RecursiveTagCount,
    greatest(tqa.QuestionScore, coalesce(tqa.PreviousQuestionScore, 0), coalesce(tqa.NextQuestionScore, 0)) as MaxNeighbouringScore,
    coalesce(nullif(trim(tqa.Title), ''), '[No Title]') || ' [' || coalesce(tqa.OwnerName, 'Anonymous') || ']' as FormattedTitle,
    case when tqa.QuestionScore > 0 then 1 else 0 end as PositiveScoreFlag
from TopQuestionsWithAnswers tqa
left join ConsolidatedUserData cud on cud.DisplayName = tqa.OwnerName
left join RecursiveTagHierarchy rt on rt.TagName = cud.TopTag
where (tqa.QuestionScore > 5 or tqa.AnswerCount > 3)
and (cud.GoldBadges + cud.SilverBadges + cud.BronzeBadges) > 0
union
select 
    p.Id,
    coalesce(p.Title, '[Deleted Title]'),
    p.Score,
    p.ViewCount,
    u.DisplayName,
    u.Reputation,
    0,
    null,
    0,
    0,
    'UnionFallback',
    u.DisplayName,
    u.Reputation,
    'none',
    0,
    0,
    0,
    0,
    0,
    greatest(p.Score, 0, 0),
    coalesce(nullif(trim(p.Title), ''), '[No Title]') || ' [' || coalesce(u.DisplayName, 'Anonymous') || ']',
    case when p.Score > 0 then 1 else 0 end
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
and p.Score < 0
order by MaxNeighbouringScore desc, AnswerCount desc
limit 50;