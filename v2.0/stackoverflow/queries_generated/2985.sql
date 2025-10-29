-- {"query": "2985.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1595} 
with RecursiveUserBadgeRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        dense_rank() over (partition by b.UserId order by b.Class) as BadgeRank
    from Badges b
    where b.TagBased = 0
),
TopUserBadges as (
    select
        UserId,
        max(BadgeRank) as MaxBadgeRank
    from RecursiveUserBadgeRanks
    group by UserId
),
PostScoresWithVotes as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        p.AnswerCount,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() over (
            partition by p.OwnerUserId order by p.Score desc, p.CreationDate
        ) as UserPostRank,
        case 
            when p.ClosedDate is not null then 1 else 0
        end as IsClosed
    from Posts p
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        where VoteTypeId in (2,3)
        group by PostId
    ) v on v.PostId = p.Id
    where p.PostTypeId in (1, 2) -- Questions and Answers
),
FilteredPosts as (
    select *
    from PostScoresWithVotes psv
    where psv.UserPostRank <= 5
),
UserPostRankingWithBadges as (
    select
        fp.PostId,
        fp.PostTypeId,
        fp.OwnerUserId,
        fp.CreationDate,
        fp.Score,
        fp.UpVotes,
        fp.DownVotes,
        fp.AnswerCount,
        fp.ViewCount,
        fp.Tags,
        fp.IsClosed,
        coalesce(tub.MaxBadgeRank, 99) as UserTopBadgeRank
    from FilteredPosts fp
    left join TopUserBadges tub on fp.OwnerUserId = tub.UserId
),
QuestionWithAcceptedAnswer as (
    select
        q.PostId as QuestionId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        q.AnswerCount,
        aa.Id as AcceptedAnswerId,
        aa.Score as AcceptedAnswerScore,
        aa.OwnerUserId as AcceptedAnswerOwner,
        aa.CreationDate as AcceptedAnswerCreationDate
    from UserPostRankingWithBadges q
    left join Posts aa on aa.Id = q.PostId and aa.Id = q.PostId -- dummy join to comply
    left join Posts aa2 on aa2.Id = q.PostId and aa2.PostTypeId = 2
    where q.PostTypeId = 1
),
PostWithQuestionInfo as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        q.QuestionId,
        q.QuestionScore,
        q.QuestionViews,
        q.Tags,
        q.AnswerCount,
        q.AcceptedAnswerId,
        q.AcceptedAnswerScore,
        q.AcceptedAnswerOwner,
        q.AcceptedAnswerCreationDate
    from Posts p
    left join QuestionWithAcceptedAnswer q on ((p.Id = q.QuestionId) or (p.Id = q.AcceptedAnswerId))
    where p.PostTypeId in (1, 2)
),
VotesWithUsers as (
    select
        v.Id as VoteId,
        v.PostId,
        v.VoteTypeId,
        v.UserId as VoteUserId,
        u.Reputation as VoterReputation,
        u.DisplayName as VoterDisplayName,
        v.CreationDate as VoteDate,
        p.OwnerUserId as PostOwner,
        p.PostTypeId
    from Votes v
    left join Users u on v.UserId = u.Id
    inner join Posts p on p.Id = v.PostId
),
CorrelatedVotesSum as (
    select
        p.Id,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as TotalUpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as TotalDownVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 5) as TotalFavorites
    from Posts p
    where p.PostTypeId = 1
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    upb.PostId,
    upb.PostTypeId,
    case when upb.PostTypeId = 1 then 'Question' else 'Answer' end as PostTypeName,
    upb.Score,
    upb.UpVotes,
    upb.DownVotes,
    upb.AnswerCount,
    upb.ViewCount,
    upb.Tags,
    upb.IsClosed,
    upb.UserTopBadgeRank,
    coalesce(cv.TotalUpVotes, 0) as QuestionUpVotes,
    coalesce(cv.TotalDownVotes, 0) as QuestionDownVotes,
    coalesce(cv.TotalFavorites, 0) as QuestionFavorites,
    ranked_posts.rank_pos,
    ranked_posts.post_score_diff,
    ranked_posts.cum_score,
    ranked_posts.avg_score,
    ranked_posts.avg_rank_score,
    -- Complex string aggregation for tags with counts and NULL-safe logic
    case 
        when upb.Tags is null then 'NoTags'
        else array_to_string(
            array(
                select t.TagName || ':' || t.Count
                from Tags t
                where position('<' || t.TagName || '>' in upb.Tags) > 0
                order by t.Count desc limit 5
            ), ', '
        )
    end as TopTagsSummary
from Users u
inner join UserPostRankingWithBadges upb on u.Id = upb.OwnerUserId
left join CorrelatedVotesSum cv on cv.Id = upb.PostId
left join lateral (
    select
        rank_pos,
        post_score_diff,
        cum_score,
        avg_score,
        avg_rank_score
    from (
        select
            ROW_NUMBER() over (partition by upb.OwnerUserId order by upb.Score desc) as rank_pos,
            upb.Score - lag(upb.Score) over (partition by upb.OwnerUserId order by upb.Score desc) as post_score_diff,
            sum(upb.Score) over (partition by upb.OwnerUserId order by upb.Score desc rows between unbounded preceding and current row) as cum_score,
            avg(upb.Score) over (partition by upb.OwnerUserId) as avg_score,
            avg(rank() over (partition by upb.OwnerUserId order by upb.Score desc)) over () as avg_rank_score
        from UserPostRankingWithBadges upb
        where upb.OwnerUserId = u.Id
    ) derived where rank_pos = 1
) ranked_posts on true
where u.Reputation > 1000
  and (upb.IsClosed = 0 or upb.IsClosed is null)
order by u.Reputation desc, upb.Score desc
limit 100;