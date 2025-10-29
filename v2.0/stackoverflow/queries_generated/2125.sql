-- {"query": "2125.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1696} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Id is not null
),
TopBadges as (
    select UserId, BadgeName, Class, Date from RecursiveUserBadges where BadgeRank <= 3
),
QuestionScores as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        coalesce(p.ViewCount, 0) as ViewCount,
        p.AcceptedAnswerId,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesCount,
        array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'),1) as TagCount
    from Posts p
    left join Comments c on p.Id = c.PostId
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId = 1 -- questions only
    group by p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AcceptedAnswerId, p.Tags
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as AnswerUpVotes
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId = 2 -- answers only
    group by p.ParentId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        coalesce(max(p.CreationDate), u.CreationDate) as LastPostDate,
        case when max(p.CreationDate) is null then u.CreationDate else max(p.CreationDate) end as ActivityDate
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
UserPostRanks as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as PostRank
    from Posts p
    where p.PostTypeId in (1,2)
),
ClosedQuestions as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId,
        max(ph.CreationDate) as ClosedDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name ilike '%duplicate%'
),
QuestionAnswerRelations as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        asw.AnswerCount,
        asw.AvgAnswerScore,
        asw.MaxAnswerScore,
        asw.AnswerUpVotes,
        cq.CloseReasonId,
        dq.RelatedPostId as DuplicateOfQuestionId
    from QuestionScores q
    left join AnswerStats asw on q.Id = asw.QuestionId
    left join ClosedQuestions cq on q.Id = cq.PostId
    left join DuplicateLinks dq on q.Id = dq.PostId
),
FinalSelectedPosts as (
    select
        qa.QuestionId,
        qa.Title,
        qa.Tags,
        qa.QuestionScore,
        qa.ViewCount,
        qa.AnswerCount,
        coalesce(qa.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(qa.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(qa.AnswerUpVotes, 0) as AnswerUpVotes,
        qa.CloseReasonId,
        qa.DuplicateOfQuestionId,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.LastPostDate,
        string_agg(distinct tb.BadgeName, ', ') filter (where tb.BadgeName is not null) as TopBadges,
        upr.PostRank as OwnerTopPostRank
    from QuestionAnswerRelations qa
    left join Users u on qa.QuestionId = u.Id
         or exists (
             select 1 from Posts p where p.Id = qa.QuestionId and p.OwnerUserId = u.Id
         )
    left join UserActivity ua on qa.QuestionId = ua.Id
    left join TopBadges tb on ua.Id = tb.UserId
    left join UserPostRanks upr on upr.PostId = qa.QuestionId and upr.OwnerUserId = ua.Id
    group by
        qa.QuestionId, qa.Title, qa.Tags, qa.QuestionScore, qa.ViewCount, qa.AnswerCount, qa.AvgAnswerScore,
        qa.MaxAnswerScore, qa.AnswerUpVotes, qa.CloseReasonId, qa.DuplicateOfQuestionId,
        u.DisplayName, u.Reputation,
        ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade, ua.LastPostDate, upr.PostRank
)
select
    fs.QuestionId,
    fs.Title,
    substring(fs.Tags from 2 for char_length(fs.Tags)-2) as CleanTags,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerCount,
    fs.AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.AnswerUpVotes,
    case 
        when fs.CloseReasonId is not null then 'Closed: ' || fs.CloseReasonId
        else 'Open'
    end as ClosedStatus,
    case
        when fs.DuplicateOfQuestionId is not null then 'Duplicate of QId: ' || fs.DuplicateOfQuestionId::text
        else 'Not duplicate'
    end as DuplicateStatus,
    fs.OwnerName,
    fs.OwnerReputation,
    fs.QuestionsPosted,
    fs.AnswersPosted,
    fs.CommentsMade,
    fs.LastPostDate,
    fs.TopBadges,
    fs.OwnerTopPostRank,
    -- calculate a weighted popularity index
    round(
        (fs.QuestionScore * 1.5 + fs.ViewCount * 0.001 + fs.AnswerCount * 2 + fs.MaxAnswerScore * 1.2 + fs.AnswerUpVotes * 1.3) 
        / nullif((fs.OwnerReputation / nullif(fs.AnswersPosted,1)),0), 2) as WeightedPopularityIndex
from FinalSelectedPosts fs
where fs.AnswerCount > 2
  and fs.ViewCount > 1000
  and (fs.CloseReasonId is null or fs.CloseReasonId::int not in (101,102)) -- not closed as duplicate or off-topic
order by WeightedPopularityIndex desc NULLS LAST, fs.ViewCount desc
limit 100;