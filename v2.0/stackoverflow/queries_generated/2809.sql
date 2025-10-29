-- {"query": "2809.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1253} 
with UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as LastBadgeRank,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopPosts as (
    select 
        p.Id, 
        p.Title, 
        p.OwnerUserId, 
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        case when p.Tags is not null 
            then array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), 1)
            else 0
        end as TagCount,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as PostRank
    from Posts p
    where p.PostTypeId in (1,2) -- questions or answers
),
PostWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.TagCount,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.FavoriteCount as AnswerFavoriteCount,
        a.RankInQuestion,
        a.IsAccepted
    from 
        (select * from TopPosts where PostTypeId=1 and PostRank <= 100) q
        left join lateral (
            select 
                a.Id, a.OwnerUserId, a.Score, a.CreationDate, a.FavoriteCount,
                row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankInQuestion,
                case when a.Id = q.AcceptedAnswerId then true else false end as IsAccepted
            from Posts a 
            where a.PostTypeId = 2 and a.ParentId = q.Id
        ) a on true
),
LatestCommentsPerPost as (
    select distinct on (c.PostId) 
        c.PostId,
        c.Id as CommentId,
        c.UserId as CommentUserId,
        c.CreationDate as CommentDate,
        c.Score as CommentScore,
        c.Text as CommentText
    from Comments c
    order by c.PostId, c.CreationDate desc
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select 
    q.QuestionId,
    left(q.Title, 100) || coalesce(' [Tags: ' || array_to_string(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), ', ') || ']', '') as ShortTitleWithTags,
    u.DisplayName as QuestionOwnerName,
    q.QuestionScore,
    q.QuestionViews,
    q.TagCount,
    q.AnswerId,
    au.DisplayName as AnswerOwnerName,
    q.AnswerScore,
    q.AnswerFavoriteCount,
    q.AnswerCreationDate,
    q.IsAccepted,
    c.CommentText as LatestCommentText,
    c.CommentScore as LatestCommentScore,
    c.CommentDate as LatestCommentDate,
    pfa.LinkedCount,
    pfa.DuplicateCount,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    case 
        when q.QuestionScore > avg(q.QuestionScore) over () then 'Above Avg Question Score' 
        else 'Below Avg Question Score' end as QuestionScoreCategory,
    -- Complex expression with NULL logic and string manipulation
    case 
        when q.AnswerFavoriteCount is null then 'No favorites'
        when q.AnswerFavoriteCount > 10 then 'Popular answer'
        else 'Less popular answer'
    end as AnswerPopularity,
    -- Correlated subquery to get number of distinct users who commented on the question
    (select count(distinct c2.UserId) from Comments c2 where c2.PostId = q.QuestionId and c2.UserId is not null) as DistinctCommenters,
    -- Window function to compute cumulative counts of answers per user
    sum(case when q.AnswerOwner is not null then 1 else 0 end) over (partition by q.AnswerOwner order by q.AnswerCreationDate rows between unbounded preceding and current row) as CumulativeAnswersByUser
from 
    PostWithAnswers q
    left join Users u on u.Id = q.QuestionOwner
    left join Users au on au.Id = q.AnswerOwner
    left join LatestCommentsPerPost c on c.PostId = q.QuestionId
    left join Posts p on p.Id = q.QuestionId
    left join PostLinkAggregates pfa on pfa.PostId = q.QuestionId
    left join UserBadgeCounts ubc on ubc.UserId = q.QuestionOwner
where 
    q.PostRank <= 100
order by 
    q.QuestionScore desc nulls last,
    q.AnswerScore desc nulls last,
    q.QuestionId
limit 50;