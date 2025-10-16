-- {"query": "612.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1431} 
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
LatestPostsPerUser as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as PostRank
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
),
TaggedQuestionsWithDupes as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.Score,
        array_agg(distinct lt.Name) filter (where lt.Name is not null) as LinkTypesToDuplicates,
        (select count(*) from Posts a where a.ParentId = q.Id and a.Score > 0) as PositiveAnswersCount,
        (select max(a.Score) from Posts a where a.ParentId = q.Id) as MaxAnswerScore,
        (select u.DisplayName from Users u where u.Id = q.OwnerUserId) as QuestionOwner,
        (select count(*) from Comments c where c.PostId = q.Id and c.Score > 1) as HighScoreCommentsCount
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.OwnerUserId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        count(distinct b.Id) as BadgesCount,
        sum(coalesce(vt.UpVotes,0)) as TotalUpVotes,
        sum(coalesce(vt.DownVotes,0)) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    where u.Reputation > 500
    group by u.Id
),
PostHistoryCloseStats as (
    select
        pht.PostId,
        count(case when pht.PostHistoryTypeId = 10 then 1 end) as CloseVotesCount,
        count(case when pht.PostHistoryTypeId = 11 then 1 end) as ReopenVotesCount,
        max(case when pht.PostHistoryTypeId = 10 then pht.CreationDate else null end) as LastCloseDate
    from PostHistory pht
    group by pht.PostId
),
QuestionsWithWindowStats as (
    select
        pq.QuestionId,
        pq.Title,
        pq.Tags,
        pq.CreationDate,
        pq.Score,
        pq.PositiveAnswersCount,
        pq.MaxAnswerScore,
        pq.QuestionOwner,
        pq.HighScoreCommentsCount,
        phcs.CloseVotesCount,
        phcs.ReopenVotesCount,
        phcs.LastCloseDate,
        rank() over (partition by pq.QuestionOwner order by pq.Score desc, pq.CreationDate desc) as UserQuestionRank,
        avg(pq.Score) over (partition by pq.QuestionOwner) as AvgUserQuestionScore,
        count(*) over (partition by pq.QuestionOwner) as UserQuestionCount
    from TaggedQuestionsWithDupes pq
    left join PostHistoryCloseStats phcs on phcs.PostId = pq.QuestionId
)
select
    u.DisplayName as User,
    uas.TotalPosts,
    uas.QuestionsCount,
    uas.AnswersCount,
    uas.BadgesCount,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    lub.BadgeName,
    lub.Class as BadgeClass,
    lpp.PostId as LatestPostId,
    lpp.Title as LatestPostTitle,
    lpp.Score as LatestPostScore,
    qws.QuestionId,
    qws.Title as TopQuestionTitle,
    qws.Score as TopQuestionScore,
    qws.PositiveAnswersCount,
    qws.MaxAnswerScore,
    qws.CloseVotesCount,
    qws.ReopenVotesCount,
    qws.LastCloseDate,
    case 
        when uas.TotalDownVotes = 0 then null
        else round(cast(uas.TotalUpVotes as numeric) / uas.TotalDownVotes,2)
    end as UpDownRatio,
    case
        when qws.Tags is not null then
            array_to_string(
                array(
                    select distinct unnest(string_to_array(replace(replace(qws.Tags, '<', ''), '>', ''), ' '))
                    order by 1
                ), ', '
            )
        else null
    end as ParsedTags,
    -- String manipulation and NULL logic example:
    case 
        when u.WebsiteUrl is null or u.WebsiteUrl = '' then 'No Website'
        else concat('Website: ', left(u.WebsiteUrl, 30), case when length(u.WebsiteUrl) > 30 then '...' else '' end)
    end as WebsiteSummary
from Users u
left join UserActivitySummary uas on uas.UserId = u.Id
left join RecursiveUserBadges lub on lub.UserId = u.Id and lub.BadgeRank = 1
left join LatestPostsPerUser lpp on lpp.OwnerUserId = u.Id and lpp.PostRank = 1
left join QuestionsWithWindowStats qws on qws.QuestionOwner = u.DisplayName and qws.UserQuestionRank = 1
where uas.TotalPosts > 10
order by uas.TotalPosts desc, qws.TopQuestionScore desc
limit 100;