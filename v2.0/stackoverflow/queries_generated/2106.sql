-- {"query": "2106.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1218} 
with RecursiveTags as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        p.OwnerUserId,
        p.Score,
        p.CreationDate
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.Count > 100
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.IsModeratorOnly,
        t2.IsRequired,
        p2.OwnerUserId,
        p2.Score,
        p2.CreationDate
    from Tags t2
    inner join Posts p2 on p2.Id = t2.ExcerptPostId
    inner join RecursiveTags rt on rt.OwnerUserId = p2.OwnerUserId
    where t2.Count > 50 and rt.Id != t2.Id
),
UserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct ph.Id) as PostEdits,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        max(ph.CreationDate) as LastEditDate,
        min(u.CreationDate) as UserCreated
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopPosts AS (
    select 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.PostTypeId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as rn
    from Posts p
    where p.PostTypeId in (1,2) and p.Score is not null
),
AnsweredQuestionsWithAnswers AS (
    select 
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerName,
        coalesce(vote_up.CountUpVotes,0) as AnswerUpVotes,
        coalesce(vote_down.CountDownVotes,0) as AnswerDownVotes,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as answer_rank
    from Posts q
    inner join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    left join (
        select PostId, count(*) as CountUpVotes from Votes where VoteTypeId = 2 group by PostId
    ) vote_up on vote_up.PostId = a.Id
    left join (
        select PostId, count(*) as CountDownVotes from Votes where VoteTypeId = 3 group by PostId
    ) vote_down on vote_down.PostId = a.Id
    where q.PostTypeId = 1 and q.AnswerCount > 0
),
FinalAggregates AS (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostEdits,
        ua.CommentCount,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        max(tp.Score) filter (where tp.rn = 1) as BestPostScore,
        max(tp.ViewCount) filter (where tp.rn = 1) as BestPostViewCount,
        count(distinct rt.Id) as DistinctPopularTags,
        count(distinct aq.AnswerId) filter (where aq.answer_rank = 1 and aq.AnswerUpVotes > aq.AnswerDownVotes) as TopAnswersCount
    from UserActivity ua
    left join RecursiveTags rt on rt.OwnerUserId = ua.UserId
    left join TopPosts tp on tp.OwnerUserId = ua.UserId
    left join AnsweredQuestionsWithAnswers aq on aq.AnswerOwnerUserId = ua.UserId
    group by ua.UserId, ua.DisplayName, ua.Reputation, ua.PostEdits, ua.CommentCount, ua.UpVotesReceived, ua.DownVotesReceived
)
select
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostEdits,
    fa.CommentCount,
    fa.UpVotesReceived,
    fa.DownVotesReceived,
    coalesce(fa.BestPostScore, 0) as BestPostScore,
    coalesce(fa.BestPostViewCount, 0) as BestPostViewCount,
    fa.DistinctPopularTags,
    fa.TopAnswersCount,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    rank() over (order by fa.Reputation desc nulls last, fa.UpVotesReceived desc nulls last) as ReputationRank,
    dense_rank() over (order by fa.TopAnswersCount desc nulls last) as TopAnswersRank
from FinalAggregates fa
left join Badges b on b.UserId = fa.UserId
where fa.Reputation > 10000 and fa.PostEdits > 5
order by ReputationRank, TopAnswersRank
limit 100;