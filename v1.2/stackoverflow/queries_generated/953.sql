-- {"query": "953.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1532} 
with RecursiveUserActivity as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.LastAccessDate,
           coalesce(u.Location, 'Unknown') as Location,
           u.Views,
           u.UpVotes,
           u.DownVotes,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
           count(distinct b.Id) as BadgesCount,
           max(b.Date) as LastBadgeDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
RankedQuestions as (
    select p.Id,
           p.OwnerUserId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.FavoriteCount,
           row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as ScoreRank,
           dense_rank() over (order by p.Score desc) as GlobalScoreRank,
           p.Tags,
           substring(p.Title from 1 for 50) as ShortTitle,
           coalesce(p.ClosedDate, timestamp '1970-01-01') as ClosedDateSafe
    from Posts p
    where p.PostTypeId = 1
),
UserTopPosts as (
    select rq.UserId,
           rq.Id as QuestionId,
           rq.CreationDate,
           rq.Score,
           rq.ViewCount,
           rq.AnswerCount,
           rq.FavoriteCount,
           rq.ScoreRank,
           rq.GlobalScoreRank,
           rq.Tags,
           rq.ShortTitle,
           rq.ClosedDateSafe
    from RankedQuestions rq
    join RecursiveUserActivity rua on rua.UserId = rq.OwnerUserId
    where rq.ScoreRank <= 3
),
PostWithDuplicates as (
    select p.Id as PostId,
           p.Title,
           p.Tags,
           p.Score,
           p.CreationDate,
           p.OwnerUserId,
           count(distinct pl2.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts p
    left join PostLinks pl2 on pl2.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl2.LinkTypeId
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Tags, p.Score, p.CreationDate, p.OwnerUserId
),
BadgedUsersWithRecentEdits as (
    select distinct b.UserId,
           b.Name as BadgeName,
           max(ph.CreationDate) over (partition by b.UserId) as LastEditDate
    from Badges b
    join PostHistory ph on ph.UserId = b.UserId
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
      and ph.CreationDate > current_date - interval '180 days'
),
UserCommentStats as (
    select c.UserId,
           count(c.Id) as TotalComments,
           avg(length(c.Text)) as AvgCommentLength,
           max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
FinalSelection as (
    select rua.UserId,
           rua.DisplayName,
           rua.Reputation,
           rua.Location,
           rua.Views,
           rua.UpVotes,
           rua.DownVotes,
           rua.QuestionsCount,
           rua.AnswersCount,
           rua.BadgesCount,
           rua.LastBadgeDate,
           utp.QuestionId,
           utp.Score as TopQuestionScore,
           utp.ViewCount as TopQuestionViews,
           utp.AnswerCount as TopQuestionAnswers,
           utp.FavoriteCount as TopQuestionFavorites,
           utp.ScoreRank,
           utp.GlobalScoreRank,
           utp.Tags as TopQuestionTags,
           pw.DuplicateCount,
           bc.BadgeName,
           bc.LastEditDate,
           cs.TotalComments,
           cs.AvgCommentLength,
           cs.LastCommentDate
    from RecursiveUserActivity rua
    left join UserTopPosts utp on utp.UserId = rua.UserId
    left join PostWithDuplicates pw on pw.PostId = utp.QuestionId
    left join BadgedUsersWithRecentEdits bc on bc.UserId = rua.UserId
    left join UserCommentStats cs on cs.UserId = rua.UserId
    where rua.Reputation > 1000 and rua.QuestionsCount > 5
)
select distinct
       fs.UserId,
       fs.DisplayName,
       fs.Reputation,
       fs.Location,
       fs.Views,
       fs.UpVotes,
       fs.DownVotes,
       fs.QuestionsCount,
       fs.AnswersCount,
       fs.BadgesCount,
       to_char(fs.LastBadgeDate, 'YYYY-MM-DD') as LastBadgeDate,
       fs.QuestionId,
       fs.TopQuestionScore,
       fs.TopQuestionViews,
       fs.TopQuestionAnswers,
       fs.TopQuestionFavorites,
       fs.ScoreRank,
       fs.GlobalScoreRank,
       -- extract individual tags from tag string (format: <tag1><tag2><tag3>)
       array_to_string(
          array(
            select unnest(string_to_array(trim(both '<>' from fs.TopQuestionTags), '><'))
            order by 1
            limit 3
          ), ', ') as TopQuestionTop3Tags,
       fs.DuplicateCount,
       fs.BadgeName,
       to_char(fs.LastEditDate, 'YYYY-MM-DD') as LastEditDate,
       fs.TotalComments,
       round(fs.AvgCommentLength, 2) as AvgCommentLength,
       to_char(fs.LastCommentDate, 'YYYY-MM-DD') as LastCommentDate,
       -- Calculate a custom weighted score combining reputation, upvotes, and top question score
       (fs.Reputation * 0.5 + fs.UpVotes * 2 + coalesce(fs.TopQuestionScore, 0) * 3) as WeightedUserScore,
       case
         when fs.DuplicateCount is null then 'No Duplicates'
         when fs.DuplicateCount > 10 then 'Many Duplicates'
         else 'Some Duplicates'
       end as DuplicateTag,
       -- Complex predicate: user is active if last access within 90 days and last comment within 60 days or last badge within 60 days
       case 
         when fs.LastBadgeDate > current_date - interval '60 days' then 'Recently Badged'
         when fs.LastCommentDate > current_date - interval '60 days' then 'Recently Commented'
         when (select max(ph.CreationDate) from PostHistory ph where ph.UserId = fs.UserId) > current_date - interval '90 days' then 'Recently Edited'
         else 'Inactive'
       end as UserActivityStatus
from FinalSelection fs
order by fs.WeightedUserScore desc, fs.Reputation desc, fs.UserId
limit 100;