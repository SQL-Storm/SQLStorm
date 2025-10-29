-- {"query": "2459.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1216} 
with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class as BadgeClass, b.Date as BadgeDate,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.TagBased = 0 or b.TagBased is null
), LatestBadges as (
    select UserId, DisplayName, BadgeName, BadgeClass, BadgeDate
    from RecursiveUserBadges
    where rn <= 3
), QuestionAnswerStats as (
    select 
        p.OwnerUserId as UserId,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        avg(case when p.PostTypeId in (1,2) then p.Score else null end) as AvgPostScore,
        count(distinct p.AcceptedAnswerId) filter (where p.AcceptedAnswerId is not null) as AcceptedAnswersCount
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId
), UserVoteImpact as (
    select 
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCount,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCount,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotesCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
), PostLinkDuplicates as (
    select pl.PostId, count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
), HighlyLinkedQuestions as (
    select p.Id, p.Title, p.Tags, pl.DuplicateCount,
        row_number() over (order by pl.DuplicateCount desc nulls last) as dup_rank
    from Posts p
    left join PostLinkDuplicates pl on pl.PostId = p.Id
    where p.PostTypeId = 1
), TagUsageStats as (
    select
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswersToTaggedQuestions,
        coalesce(b.BadgedUsersCount, 0) as UsersWithBadgeCount
    from Tags t
    left join (
        select substring(p.Tags from '<([^>]+)>') as TagName, sum(p.AnswerCount) as AnswerCount
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
        group by substring(p.Tags from '<([^>]+)>')
    ) p on p.TagName = t.TagName
    left join (
        select b.Name, count(distinct b.UserId) as BadgedUsersCount
        from Badges b
        where b.TagBased = 1
        group by b.Name
    ) b on b.Name = t.TagName
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    to_char(u.CreationDate, 'YYYY-MM-DD') as JoinedDate,
    coalesce(qas.QuestionsCount, 0) as TotalQuestions,
    coalesce(qas.AnswersCount, 0) as TotalAnswers,
    round(coalesce(qas.AvgPostScore, 0)::numeric,2) as AvgPostScore,
    coalesce(qas.AcceptedAnswersCount, 0) as AcceptedAnswers,
    coalesce(uv.UpVotesCount, 0) as UpVotesCast,
    coalesce(uv.DownVotesCount, 0) as DownVotesCast,
    coalesce(uv.FavoriteVotesCount, 0) as FavoriteVotesCast,
    array_to_string(array_agg(distinct lb.BadgeName ORDER BY lb.BadgeDate DESC), ', ') as RecentBadges,
    hlq.Title as MostDuplicatedQuestionTitle,
    hlq.DuplicateCount as QuestionDuplicateLinks,
    string_agg(distinct tus.TagName || ' (Count:' || tus.Count || ', Answers:' || tus.TotalAnswersToTaggedQuestions || ', BadgeUsers:' || tus.UsersWithBadgeCount || ')', '; ' ORDER BY tus.Count DESC) as TagStatsSummary
from Users u
left join QuestionAnswerStats qas on qas.UserId = u.Id
left join UserVoteImpact uv on uv.UserId = u.Id
left join LatestBadges lb on lb.UserId = u.Id
left join LATERAL (
    select hlq.Title, hlq.DuplicateCount
    from HighlyLinkedQuestions hlq
    join Posts p on p.OwnerUserId = u.Id and p.Id = hlq.Id
    order by hlq.DuplicateCount desc nulls last
    limit 1
) hlq on true
cross join lateral (
    select * from TagUsageStats tus
    order by tus.Count desc
    limit 5
) tus
group by 
    u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate,
    qas.QuestionsCount, qas.AnswersCount, qas.AvgPostScore, qas.AcceptedAnswersCount,
    uv.UpVotesCount, uv.DownVotesCount, uv.FavoriteVotesCount,
    hlq.Title, hlq.DuplicateCount
order by u.Reputation desc nulls last
limit 50;