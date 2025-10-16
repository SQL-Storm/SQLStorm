-- {"query": "751.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1371} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date asc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Id is not null
),
UserTopBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostTagExtract as (
    select
        p.Id as PostId,
        p.Title,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
RecentHighScoreAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        u.Id as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        dense_rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2 and a.CreationDate > now() - interval '1 year'
),
QuestionAnswerAggregates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.OwnerUserId,
        q.CreationDate as QuestionCreationDate,
        max(a.AnswerScore) as MaxAnswerScore,
        count(a.AnswerId) filter (where a.AnswerScore > 10) as HighScoreAnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.OwnerUserId, q.CreationDate
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on ph.Comment::int = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
        row_number() over (order by count(distinct p.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > now() - interval '1 year'
    left join Comments c on c.UserId = u.Id and c.CreationDate > now() - interval '1 year'
    left join Votes v on v.UserId = u.Id and v.CreationDate > now() - interval '1 year'
    group by u.Id, u.DisplayName
),
QuestionsWithDuplicates as (
    select
        q.Id as QuestionId,
        q.Title,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title
),
TopTagsByCount as (
    select
        TagName,
        Count,
        row_number() over (order by Count desc) as TagRank
    from Tags
    where IsModeratorOnly = 0
)
select
    q.QuestionId,
    q.Title as QuestionTitle,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.MaxAnswerScore,
    q.HighScoreAnswerCount,
    coalesce(crc.CloseCount, 0) as CloseVotes,
    coalesce(qd.DuplicateCount, 0) as DuplicateLinks,
    array_agg(distinct pte.Tag) filter (where pte.Tag is not null) as Tags,
    u.DisplayName as QuestionOwner,
    ua.PostsCount as OwnerPostsLastYear,
    ua.CommentsCount as OwnerCommentsLastYear,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    string_agg(distinct utb.BadgeName || '(' || utb.Class || ')', ', ') as TopBadges,
    string_agg(distinct concat('Ans:', rha.AnswerId, '-', rha.AnswerScore, '-', rha.AnswerOwnerName), ', ') filter (where rha.AnswerRank <= 2) as TopAnswersLastYear,
    tt.TagName as PopularTag,
    tt.Count as PopularTagCount
from QuestionAnswerAggregates q
left join CloseReasonCounts crc on q.QuestionId = crc.PostId
left join QuestionsWithDuplicates qd on q.QuestionId = qd.QuestionId
left join PostTagExtract pte on pte.PostId = q.QuestionId
left join Users u on q.OwnerUserId = u.Id
left join UserActivityWindow ua on ua.UserId = u.Id
left join UserTopBadges utb on utb.UserId = u.Id
left join RecentHighScoreAnswers rha on rha.QuestionId = q.QuestionId and rha.AnswerRank <= 2
left join TopTagsByCount tt on tt.TagName = any(array_agg(distinct pte.Tag))
group by
    q.QuestionId, q.Title, q.QuestionScore, q.ViewCount, q.AnswerCount, q.MaxAnswerScore, q.HighScoreAnswerCount,
    crc.CloseCount, qd.DuplicateCount, u.DisplayName, ua.PostsCount, ua.CommentsCount, ua.UpVotesReceived, ua.DownVotesReceived,
    tt.TagName, tt.Count
order by q.QuestionScore desc, q.ViewCount desc
limit 100;