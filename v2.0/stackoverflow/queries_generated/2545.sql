-- {"query": "2545.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1490} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopUserBadges as (
    select * from RecursiveUserBadges where BadgeRank <= 3
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.VoteTypeId = 2::int)::int,0) as TotalUpvotesGiven,
        coalesce(sum(v.VoteTypeId = 3::int)::int,0) as TotalDownvotesGiven,
        -- Average score of user's posts with handling division by zero
        case 
            when count(p.Id) = 0 then null 
            else round(avg(p.Score)::numeric,2) 
        end as AvgPostScore,
        -- Last activity date among posts and comments
        greatest(
            coalesce(max(p.LastActivityDate), '1970-01-01'::timestamp),
            coalesce(max(c.CreationDate), '1970-01-01'::timestamp)
        ) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionDuplicates as (
    select pl.PostId, count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    group by pl.PostId
),
PostScores as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        -- count comments per post
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        -- flag for whether the post is closed
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        -- duplicate count if question
        coalesce(qd.DuplicateCount, 0) as DuplicateCount
    from Posts p
    left join QuestionDuplicates qd on p.Id = qd.PostId
    where p.PostTypeId in (1, 2) -- questions and answers
),
AnswerRanks as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2 and p.ParentId is not null
),
HighScoringAcceptedAnswers as (
    select 
        p.Id as QuestionId,
        p.Title,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.AnswerRank
    from Posts p
    inner join Posts a on a.Id = p.AcceptedAnswerId
    inner join AnswerRanks ar on ar.Id = a.Id
    where p.PostTypeId = 1 and a.Score > 10 and ar.AnswerRank > 1
),
TagPopularity as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag,
        count(*) as TagUsageCount,
        avg(p.Score) as AvgScorePerTag
    from Posts p
    where p.PostTypeId = 1
    group by Tag
),
RecentEdits as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        json_agg(distinct ph.UserId order by ph.CreationDate desc) filter (where ph.UserId is not null) as EditorsUserIds
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Title, Body, Tags edits only
    group by ph.PostId
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.TotalUpvotesGiven,
    ua.TotalDownvotesGiven,
    ua.AvgPostScore,
    ua.LastActivity,
    string_agg(distinct tub.BadgeName || '(' || 
        case tub.Class 
            when 1 then 'Gold' 
            when 2 then 'Silver' 
            when 3 then 'Bronze' 
            else 'Unknown' end || ')', ', ') as TopBadges,
    ps.Id as PostId,
    ps.Title as PostTitle,
    ps.PostTypeId,
    ps.Score as PostScore,
    ps.ViewCount,
    ps.CommentCount,
    ps.IsClosed,
    ps.DuplicateCount,
    re.LastEditDate,
    -- rank posts by score within the user
    rank() over (partition by ua.UserId order by ps.Score desc nulls last) as PostScoreRank,
    -- tag popularity for tags in those posts
    array_agg(distinct tp.Tag || ':' || tp.TagUsageCount::text || '(' || round(tp.AvgScorePerTag::numeric,2)::text || ')') filter (
        where ps.Tags is not null and tp.Tag is not null and strpos(ps.Tags, '<' || tp.Tag || '>') > 0
    ) as PostTagsPopularity,
    -- existence of high scoring accepted answer with not highest rank
    exists (
        select 1 from HighScoringAcceptedAnswers hsa where hsa.QuestionId = ps.Id
    ) as HasHighScoreAcceptedAnswerNotTopRank
from UserActivity ua
left join TopUserBadges tub on tub.UserId = ua.UserId
left join PostScores ps on ps.OwnerUserId = ua.UserId
left join RecentEdits re on re.PostId = ps.Id
left join TagPopularity tp on strpos(ps.Tags, '<' || tp.Tag || '>') > 0
where ua.LastActivity > (current_timestamp - interval '180 day')
group by ua.UserId, ua.DisplayName, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade,
    ua.TotalUpvotesGiven, ua.TotalDownvotesGiven, ua.AvgPostScore, ua.LastActivity,
    ps.Id, ps.Title, ps.PostTypeId, ps.Score, ps.ViewCount, ps.CommentCount, ps.IsClosed,
    ps.DuplicateCount, re.LastEditDate
order by ua.Reputation desc nulls last, ua.UserId, ps.Score desc nulls last
limit 100;