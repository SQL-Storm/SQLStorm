with UserActivity as (
    select
        u.Id as UserId,
        coalesce(u.Reputation, 0) as Reputation,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end), 0) as QuestionsPosted,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end), 0) as AnswersPosted,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotesReceived,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotesReceived,
        coalesce(count(distinct b.Id), 0) as BadgesEarned
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
    left join Votes v on v.PostId = p.Id and v.VoteTypeId in (2, 3)
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation
), 
TopTagsByUser as (
    select
        p.OwnerUserId as UserId,
        tag.tag as TagName,
        count(*) as TagCount,
        row_number() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
    from Posts p,
    lateral (
      select regexp_split_to_table(coalesce(p.Tags, ''), '><') as tag
    ) tag
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId, tag.tag
), 
RecentHotQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotes,
        row_number() over (order by p.CreationDate desc) as Rn
    from Posts p
    left join Votes v on v.PostId = p.Id and v.VoteTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.CreationDate
    having coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) > 10
), 
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as integer) end) as CloseReasonId,
        max(cr.Name) as CloseReasonName,
        p.Title,
        p.CreationDate,
        p.Score
    from PostHistory ph
    left join CloseReasonTypes cr on cr.Id = cast(ph.Comment as integer)
    join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, p.Title, p.CreationDate, p.Score
), 
AnswerCountsPerQuestion as (
    select
        p.Id as QuestionId,
        p.Title,
        count(a.Id) as TotalAnswers,
        count(case when a.Score > 0 then 1 end) as PositiveScoreAnswers,
        count(case when a.OwnerUserId is null then 1 end) as AnonymousAnswers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title
),
UsersWithWorstBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        dense_rank() over (partition by u.Id order by b.Class desc) as WorstBadgeRank
    from Users u
    join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Name, b.Class
),
UserLatestComment as (
    select
        UserId,
        Id as CommentId,
        Text,
        CreationDate
    from (
      select
        c.*,
        row_number() over (partition by c.UserId order by c.CreationDate desc) as rn
      from Comments c
      where c.UserId is not null
    ) t
    where t.rn = 1
)
select
    ua.UserId,
    u.DisplayName,
    ua.Reputation,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ua.BadgesEarned,
    (select array_agg(tt.TagName order by tt.TagCount desc) 
     from TopTagsByUser tt 
     where tt.UserId = ua.UserId and tt.TagRank <= 5) as TopTags,
    coalesce(rhq.Title, 'N/A') as LatestHotQuestionTitle,
    coalesce(rhq.UpVotes, 0) as LatestHotQuestionUpVotes,
    coalesce(cqwr.CloseReasonName, 'Not Closed') as CloseReason,
    ac.TotalAnswers,
    ac.PositiveScoreAnswers,
    ac.AnonymousAnswers,
    uwb.BadgeName as WorstBadgeName,
    uwb.WorstBadgeRank,
    coalesce(ulc.Text, '') as LatestComment,
    case
        when ua.Reputation < 100 then 'Low'
        when ua.Reputation between 100 and 1000 then 'Medium'
        else 'High'
    end as ReputationCategory,
    case
        when ua.QuestionsPosted = 0 and ua.AnswersPosted > 0 then 'Answerer Only'
        when ua.AnswersPosted = 0 and ua.QuestionsPosted > 0 then 'Asker Only'
        when ua.AnswersPosted > 0 and ua.QuestionsPosted > 0 then 'Both'
        else 'Inactive'
    end as UserActivityType
from UserActivity ua
join Users u on u.Id = ua.UserId
left join RecentHotQuestions rhq on rhq.Rn = 1
left join ClosedQuestionsWithReasons cqwr on cqwr.PostId = (
    select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1 order by p.CreationDate desc fetch first 1 row only
)
left join AnswerCountsPerQuestion ac on ac.QuestionId = (
    select p.Id from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1 order by p.CreationDate desc fetch first 1 row only
)
left join UsersWithWorstBadges uwb on uwb.UserId = ua.UserId and uwb.WorstBadgeRank = 1
left join UserLatestComment ulc on ulc.UserId = ua.UserId
where ua.Reputation is not null
order by ua.Reputation desc
fetch first 100 rows only;