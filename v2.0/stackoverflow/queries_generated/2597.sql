-- {"query": "2597.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1510} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(vt.Name = 'UpMod'::text)::int, 0) as UpVotesReceived,
        coalesce(sum(vt.Name = 'DownMod'::text)::int, 0) as DownVotesReceived,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on v.VoteTypeId = vt.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedUserActivity as (
    select
        UserId,
        DisplayName,
        Reputation,
        CreationDate,
        QuestionsAsked,
        AnswersGiven,
        UpVotesReceived,
        DownVotesReceived,
        LastPostRank,
        case
            when Reputation >= 10000 then 'Expert'
            when Reputation >= 1000 then 'Intermediate'
            else 'Beginner'
        end as UserLevel,
        coalesce((
            select string_agg(b.Name || '(' || b.Class || ')', ', ')
            from Badges b
            where b.UserId = ru.UserId
              and b.Date > ru.CreationDate
        ), 'No badges') as BadgesList
    from RecursiveUserActivity ru
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(aa.AverageAnswerScore, 0) as AverageAnswerScore,
        coalesce(la.LatestAnswerDate, null) as LatestAnswerDate
    from Posts q
    left join (
        select ParentId, count(*) AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    left join (
        select ParentId, avg(Score) AverageAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) aa on aa.ParentId = q.Id
    left join (
        select ParentId, max(CreationDate) LatestAnswerDate
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) la on la.ParentId = q.Id
    where q.PostTypeId = 1
),
PostCloseHistory as (
    select 
        ph.PostId,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as ClosedDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as ReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then crt.Name else null end) as CloseReasonName
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id::text = ph.Comment
    group by ph.PostId
),
FilteredPosts as (
    select p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1 
      and p.CreationDate > current_date - interval '1 year'
      and p.Score > 0
),
DuplicatePosts as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
UserCommentsAndVotes as (
    select
        u.Id as UserId,
        count(distinct c.Id) as TotalComments,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as VoteUps,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as VoteDowns,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Users u
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on v.VoteTypeId = vt.Id
    group by u.Id
),
TopTags as (
    select
        t.TagName,
        t.Count,
        ts.ExcerptPostId,
        ts.WikiPostId,
        rank() over (order by t.Count desc) as TagRank
    from Tags t
    left join Tags ts on ts.Id = t.Id
    where t.TagName is not null
)
select
    ru.UserId,
    ru.DisplayName,
    ru.UserLevel,
    ru.Reputation,
    ru.QuestionsAsked,
    ru.AnswersGiven,
    ru.UpVotesReceived,
    ru.DownVotesReceived,
    ru.BadgesList,
    pa.Title as RecentPopularQuestion,
    pa.Score as QuestionScore,
    pa.ViewCount,
    pa.AnswerCount,
    pa.AverageAnswerScore,
    pch.CloseReasonName,
    uc.TotalComments,
    uc.VoteUps,
    uc.VoteDowns,
    uc.Favorites,
    tt.TagName as TopTag,
    tt.Count as TagCount,
    tt.TagRank,
    length(ru.DisplayName || coalesce(ru.BadgesList, '')) as DisplayBadgeNameCharLength,
    case when ru.Reputation > 5000 and uc.TotalComments > 100 then 'Highly active' else 'Less active' end as ActivityClassification,
    array_to_string(array(
        select distinct substring(tg.TagName from 1 for 3) 
        from Tags tg 
        join Posts p on p.Tags like '%' || tg.TagName || '%'
        where p.OwnerUserId = ru.UserId
        limit 3
    ), ', ') as SampleUserTags,
    (select count(*) 
     from Posts p2 
     where p2.OwnerUserId = ru.UserId and p2.Score > (pa.QuestionScore / nullif(pa.AnswerCount,0) + 1)
    ) as HighScorePostsCount
from RankedUserActivity ru
left join PostAnswerStats pa on pa.CreationDate = (
    select max(CreationDate)
    from Posts p2
    where p2.OwnerUserId = ru.UserId and p2.PostTypeId = 1
)
left join PostCloseHistory pch on pch.PostId = pa.QuestionId
left join UserCommentsAndVotes uc on uc.UserId = ru.UserId
left join TopTags tt on tt.TagRank = 1
where ru.Reputation > 1000
order by ru.Reputation desc, pa.Score desc
limit 100;