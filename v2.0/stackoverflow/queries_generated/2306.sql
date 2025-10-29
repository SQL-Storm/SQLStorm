-- {"query": "2306.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1467} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000 and (b.Class = 1 or b.Class is null)
),
PostScoreStats as (
    select 
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        avg(p.Score) as AvgScore,
        percentile_cont(0.5) within group (order by p.Score) as MedianScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
LatestPostHistoryPerPost as (
    select ph1.PostId, ph1.Id, ph1.PostHistoryTypeId, ph1.CreationDate, ph1.UserId, ph1.Comment,
           row_number() over (partition by ph1.PostId order by ph1.CreationDate desc, ph1.Id desc) as rn
    from PostHistory ph1
    where ph1.PostHistoryTypeId in (10,11,12,13) -- Close, Reopen, Delete, Undelete
),
PostsWithLatestPH as (
    select p.Id as PostId, p.Title, p.OwnerUserId, lph.PostHistoryTypeId, lph.CreationDate as PHDate, lph.Comment as PHComment,
           p.Score, p.ViewCount, p.CreationDate,
           case 
             when lph.PostHistoryTypeId = 10 then 'Closed' 
             when lph.PostHistoryTypeId = 11 then 'Reopened'
             when lph.PostHistoryTypeId = 12 then 'Deleted'
             when lph.PostHistoryTypeId = 13 then 'Undeleted'
             else 'Open' end as PostStatus
    from Posts p
    left join LatestPostHistoryPerPost lph on lph.PostId = p.Id and lph.rn = 1
),
AnswersWithQuestionScores as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        q.Title as QuestionTitle,
        a.Score as AnswerScore,
        q.Score as QuestionScore,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as AnswerRankForQuestion
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
),
UserRecentActivity as (
    select u.Id as UserId, u.DisplayName, max(ph.CreationDate) as LastEditDate, 
           max(v.CreationDate) as LastVoteDate,
           max(coalesce(p.LastActivityDate, p.CreationDate)) as LastPostActivity
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionTagExploded as (
    select
        p.Id as PostId,
        trim(both '<>' from unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'))) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TopTagsByPopularity as (
    select 
        t.TagName,
        count(distinct q.PostId) as QuestionCount,
        sum(coalesce(q.Score,0)) as TotalTagScore,
        avg(coalesce(q.Score,0)) as AvgTagScore,
        max(coalesce(q.Score,0)) as MaxTagScore
    from QuestionTagExploded t
    join Posts q on q.Id = t.PostId
    group by t.TagName
    order by QuestionCount desc
    limit 10
)

select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(props.QuestionCount,0) as QuestionsPosted,
    coalesce(props.AnswerCount,0) as AnswersPosted,
    round(coalesce(props.AvgScore, 0)::numeric,2) as AveragePostScore,
    coalesce(b.BadgeName, 'No Gold Badge') as TopBadge,
    ph.PostStatus,
    ph.PHDate,
    ph.PHComment,
    ua.LastEditDate,
    ua.LastVoteDate,
    ua.LastPostActivity,
    tt.TagName as FavoriteTopTag,
    tt.QuestionCount as FavoriteTagQuestionCount,
    tt.TotalTagScore as FavoriteTagTotalScore,
    tt.AvgTagScore as FavoriteTagAvgScore,
    tt.MaxTagScore as FavoriteTagMaxScore,
    array_agg(distinct concat_ws(':', a.QuestionTitle, a.AnswerScore::text)) filter (where a.AnswerRankForQuestion <= 3) as TopAnswerScoresForQuestions
from Users u
left join PostScoreStats props on props.OwnerUserId = u.Id
left join RecursiveUserBadges b on b.UserId = u.Id and b.rn = 1
left join PostsWithLatestPH ph on ph.OwnerUserId = u.Id
left join UserRecentActivity ua on ua.UserId = u.Id
left join lateral (
    select tt1.TagName, tt1.QuestionCount, tt1.TotalTagScore, tt1.AvgTagScore, tt1.MaxTagScore
    from TopTagsByPopularity tt1
    join QuestionTagExploded qte on qte.TagName = tt1.TagName 
    join Posts p on p.Id = qte.PostId and p.OwnerUserId = u.Id
    group by tt1.TagName, tt1.QuestionCount, tt1.TotalTagScore, tt1.AvgTagScore, tt1.MaxTagScore
    order by tt1.QuestionCount desc limit 1
) tt on true
left join AnswersWithQuestionScores a on a.AnswerId in (
    select Id from Posts where OwnerUserId = u.Id and PostTypeId = 2
)
group by u.Id,u.DisplayName,u.Reputation,props.QuestionCount,props.AnswerCount,props.AvgScore,b.BadgeName,
         ph.PostStatus,ph.PHDate,ph.PHComment,
         ua.LastEditDate, ua.LastVoteDate, ua.LastPostActivity,
         tt.TagName, tt.QuestionCount, tt.TotalTagScore, tt.AvgTagScore, tt.MaxTagScore
order by u.Reputation desc
limit 100;