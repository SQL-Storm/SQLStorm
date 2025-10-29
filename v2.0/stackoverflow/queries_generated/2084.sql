-- {"query": "2084.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1501} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from 
        Users u
        left join Badges b on u.Id = b.UserId
    where 
        b.Class is not null
),
RecentPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        case 
            when p.PostTypeId = 1 then 'Question'
            when p.PostTypeId = 2 then 'Answer'
            else 'Other'
        end as PostTypeName
    from 
        Posts p
    where 
        p.CreationDate > current_date - interval '90 days'
),
AnswerStats as (
    select 
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighScoreAnswers
    from 
        Posts a
    where 
        a.PostTypeId = 2
        and a.CreationDate > current_date - interval '90 days'
    group by a.ParentId
),
PostLinkAgg as (
    select 
        pl.PostId,
        count(distinct pl.RelatedPostId) as LinksCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinksCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    group by pl.PostId
),
UserActivityRanks as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesCast,
        dense_rank() over (order by count(distinct p.Id) desc) as PostsRank,
        dense_rank() over (order by count(distinct c.Id) desc) as CommentsRank,
        dense_rank() over (order by count(distinct v.Id) filter (where v.VoteTypeId = 2) desc) as UpVotesRank
    from 
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Comments c on c.UserId = u.Id
        left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopTagsPerUser as (
    select 
        u.Id as UserId,
        tag,
        count(*) as TagUseCount,
        row_number() over (partition by u.Id order by count(*) desc) as rn
    from 
        Users u
        join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
        cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tag
    group by u.Id, tag
)
select distinct 
    ru.UserId,
    ru.DisplayName,
    -- badges aggregated
    string_agg(concat(RUB.BadgeName, '(', RUB.Class, ')'), ', ') filter (where RUB.rn <= 3) as TopBadges,
    -- user activity ranks
    uar.PostsCount,
    uar.CommentsCount,
    uar.UpVotesCast,
    uar.DownVotesCast,
    uar.PostsRank,
    uar.CommentsRank,
    uar.UpVotesRank,
    -- most common tags
    coalesce(
        (select string_agg(tag, ', ') 
         from TopTagsPerUser ttp where ttp.UserId = ru.UserId and ttp.rn <= 3),
         'No Tags') as TopTags,
    -- aggregate questions with answer stats
    (
        select json_agg(json_build_object(
            'QuestionId', rp.Id,
            'Title', rp.Title,
            'Score', rp.Score,
            'ViewCount', rp.ViewCount,
            'AnswerCount', coalesce(ast.AnswerCount,0),
            'AvgAnswerScore', round(coalesce(ast.AvgAnswerScore,0)::numeric,2),
            'HighScoreAnswers', coalesce(ast.HighScoreAnswers, 0),
            'DuplicateLinks', coalesce(pla.DuplicateLinksCount, 0)
        )) 
        from RecentPosts rp
        left join AnswerStats ast on rp.Id = ast.QuestionId
        left join PostLinkAgg pla on rp.Id = pla.PostId
        where rp.OwnerUserId = ru.UserId
          and rp.PostTypeId = 1
          and rp.Score >= 5
          and rp.ViewCount > 100
          and rp.Title is not null
        limit 5
    ) as RecentPopularQuestions,
    -- last 3 comments text with NULL handling and string operations
    (
        select string_agg(
            left(coalesce(comment_text, '[No Text]'), 120) || 
            case when length(coalesce(comment_text, '')) > 120 then '...' else '' end, 
            ' ||| '
        )
        from (
            select 
                c.Text as comment_text
            from Comments c
            where c.UserId = ru.UserId
            order by c.CreationDate desc
            limit 3
        ) q
    ) as RecentCommentsSnippets,
    -- weighted score window function over answers
    (
        select round(avg(weighted_score)::numeric, 3) from (
            select 
                a.Score * exp(-extract(epoch from (current_timestamp - a.CreationDate))/86400/30) as weighted_score
            from Posts a
            where a.OwnerUserId = ru.UserId and a.PostTypeId = 2
            and a.CreationDate is not null
        ) ws
    ) as WeightedAnswerScore,
    -- exists correlated subquery to check if user has posted accepted answers recently
    exists (
        select 1
        from Posts p
        where p.OwnerUserId = ru.UserId and p.PostTypeId = 2
        and p.Id in (
            select q.AcceptedAnswerId
            from Posts q
            where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
            and q.CreationDate > current_date - interval '180 days'
        )
    ) as HasRecentAcceptedAnswer
from
    RecursiveUserBadges ru
    left join UserActivityRanks uar on ru.UserId = uar.Id
where ru.rn = 1
order by uar.PostsCount desc nulls last, ru.UserId
limit 25;