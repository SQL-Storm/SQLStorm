-- {"query": "2290.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1543}
with RankedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2
),
QuestionStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        u.DisplayName as QuestionOwner,
        coalesce(q.Score,0) as QuestionScore,
        coalesce(q.ViewCount,0) as ViewCount,
        coalesce(q.AnswerCount,0) as AnswerCount,
        coalesce(bestAns.Score,0) as BestAnswerScore,
        bestAns.OwnerName as BestAnswerOwner,
        count(distinct c.Id) filter (where c.UserId is not null) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        string_agg(tag, ',' order by tag) as TagsList
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join RankedAnswers bestAns on bestAns.ParentId = q.Id and bestAns.AnswerRank = 1
    left join Comments c on c.PostId = q.Id
    left join Votes v on v.PostId = q.Id
    cross join lateral (
        select unnest(string_to_array(substring(coalesce(q.Tags,'' ) from 2 for (char_length(q.Tags)-2)), '><')) as tag
    ) tags(tag)
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, u.DisplayName, q.Score, q.ViewCount, q.AnswerCount, bestAns.Score, bestAns.OwnerName
),
BadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        dense_rank() over (partition by b.Class order by count(*) desc) as BadgeRank
    from Badges b
    where b.TagBased = false
    group by b.UserId, b.Class
),
TopBadgeUsers as (
    select distinct UserId
    from BadgeRanks
    where BadgeRank <= 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        max(p.CreationDate) as LastPostDate,
        coalesce(sum(vup.CountUpVotes),0) as TotalUpVotes,
        coalesce(sum(vdown.CountDownVotes),0) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join lateral (
        select count(*) as CountUpVotes
        from Votes v
        where v.PostId = p.Id and v.VoteTypeId = 2
    ) vup on true
    left join lateral (
        select count(*) as CountDownVotes
        from Votes v
        where v.PostId = p.Id and v.VoteTypeId = 3
    ) vdown on true
    group by u.Id, u.DisplayName, u.Reputation
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        q.Title as QuestionTitle,
        dup.Title as DuplicateOfTitle
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
    join Posts q on pl.PostId = q.Id and q.PostTypeId = 1
    join Posts dup on pl.RelatedPostId = dup.Id and dup.PostTypeId = 1
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        q.Title,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer) and ph.PostHistoryTypeId = 10
    join Posts q on ph.PostId = q.Id and q.PostTypeId = 1
    where ph.CreationDate is not null and ph.Comment ~ '^\d+$'
)
select
    qs.QuestionId,
    qs.Title,
    qs.QuestionOwner,
    qs.QuestionScore,
    qs.ViewCount,
    qs.AnswerCount,
    qs.BestAnswerScore,
    qs.BestAnswerOwner,
    qs.CommentCount,
    qs.UpVotes,
    qs.DownVotes,
    coalesce(case when lower(qs.TagsList) like '%sql%' then 'Contains SQL tag' else null end, 'No SQL tag') as SqlTagPresence,
    uact.DisplayName as TopContributor,
    uact.Reputation,
    uact.QuestionsCount,
    uact.AnswersCount,
    dup.DuplicateOfTitle,
    closed.CloseReason,
    closed.CloseDate,
    char_length(qs.Title) as TitleLength,
    case when qs.QuestionScore > 0 and qs.AnswerCount > 0 then cast((cast(qs.BestAnswerScore as double precision) / NULLIF(qs.QuestionScore,0)) as numeric(5,2)) else null end as BestAnswerRatio,
    string_agg(b.Name, ',' order by b.Name) filter (where b.UserId is not null) as BaseBadges,
    case when qs.AnswerCount = 0 then 'Unanswered' else 'Answered' end as AnswerStatus
from QuestionStats qs
left join UserActivity uact on uact.UserId = (
    select pa.OwnerUserId
    from Posts pa
    where pa.ParentId = qs.QuestionId and pa.PostTypeId = 2
    order by pa.Score desc nulls last, pa.CreationDate asc
    limit 1
)
left join DuplicateLinks dup on dup.PostId = qs.QuestionId
left join ClosedQuestionsWithReason closed on closed.PostId = qs.QuestionId
left join Badges b on b.UserId = uact.UserId and b.TagBased = false
where (qs.AnswerCount > 0 or qs.ViewCount > 1000)
and (qs.QuestionScore > 10 or qs.BestAnswerScore > 10)
and (uact.Reputation between 1000 and 1000000 or dup.PostId is not null)
group by 
    qs.QuestionId, qs.Title, qs.QuestionOwner, qs.QuestionScore, qs.ViewCount, qs.AnswerCount,
    qs.BestAnswerScore, qs.BestAnswerOwner, qs.CommentCount, qs.UpVotes, qs.DownVotes, qs.TagsList,
    uact.DisplayName, uact.Reputation, uact.QuestionsCount, uact.AnswersCount,
    dup.DuplicateOfTitle, closed.CloseReason, closed.CloseDate
order by qs.ViewCount desc, qs.QuestionScore desc
limit 100;