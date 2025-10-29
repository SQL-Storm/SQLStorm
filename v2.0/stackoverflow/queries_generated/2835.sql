-- {"query": "2835.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1816} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as TagPath
    from Tags t
    where t.IsModeratorOnly = 0 and t.Count > 1000

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.TagPath || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on r.TagPath[array_length(r.TagPath,1)] <> t2.Id
    where t2.IsRequired = 1 and t2.Count > 500
      and not t2.Id = any(r.TagPath)
      and t2.Count < r.Count
),
TopActiveUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(u.WebsiteUrl, 'N/A') as Website,
        coalesce(u.Location,'Unknown') as Location,
        count(distinct p.Id) as PostsCount,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc, count(distinct p.Id) desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.WebsiteUrl, u.Location
    having count(distinct p.Id) > 50
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AcceptedAnswerId,
        coalesce(a.AnswersCount,0) as AnswersCount,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        (select max(pv.CreationDate)
         from PostHistory pv
         where pv.PostId = q.Id and pv.PostHistoryTypeId in (10,11)) as LastCloseReopenDate,
        (select case when count(pl.Id) > 0 then 'Yes' else 'No' end
         from PostLinks pl
         where pl.PostId = q.Id and pl.LinkTypeId = 3) as HasDuplicates
    from Posts q
    left join (
        select ParentId, count(*) as AnswersCount, avg(Score) as Score
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    where q.PostTypeId = 1
),
RankedAnswers as (
    select 
        a.Id,
        a.ParentId as QuestionId,
        a.CreationDate,
        a.Score,
        a.OwnerUserId,
        u.DisplayName,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserEngagement as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsPosted,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
FinalResults as (
    select
        qas.QuestionId,
        qas.Title,
        qas.CreationDate as QuestionCreatedOn,
        qas.QuestionScore,
        qas.ViewCount,
        qas.AnswersCount,
        qas.AvgAnswerScore,
        qas.HasDuplicates,
        r1.Id as TopAnswerId,
        r1.DisplayName as TopAnswerer,
        r1.Score as TopAnswerScore,
        r1.IsAccepted,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesReceived,
        ua.GoldBadges,
        rt.TagName,
        concat_ws(' | ', coalesce(ua.DisplayName, 'Anonymous'), coalesce(ua.Location, 'No Location'), coalesce(ua.Website, 'No Website')) as UserSummary,
        case 
            when qas.LastCloseReopenDate is null then 'Never Closed' 
            else to_char(qas.LastCloseReopenDate, 'YYYY-MM-DD') 
        end as CloseReopenInfo,
        length(coalesce(qas.Title, '')) as TitleLength,
        coalesce(nullif(trim(qas.Title),''), 'NO TITLE') as NormalizedTitle,
        string_agg(distinct pt.Name, ', ') over (partition by qas.QuestionId) as PostTypeNames
    from QuestionAnswerStats qas
    left join RankedAnswers r1 on r1.QuestionId = qas.QuestionId and r1.AnswerRank = 1
    left join UserEngagement ua on ua.UserId = r1.OwnerUserId
    left join RecursiveTagHierarchy rt on rt.Id = any (
        select unnest(string_to_array(substring(t.Tags from '\<(.*?)\>'), '><'))::int
        from Posts t where t.Id = qas.QuestionId limit 1
    )
    left join PostTypes pt on pt.Id = (select PostTypeId from Posts where Id = qas.QuestionId)
    where qas.AnswersCount > 3
      and qas.QuestionScore > 5
),
UnionedSet as (
    select DisplayName, Reputation, Location, 'TopActiveUser' as Category from TopActiveUsers
    union
    select DisplayName, null as Reputation, Location, 'Answerer' from UserEngagement where AnswersPosted > 100
    union
    select null, null, Location, 'TagModeratorArea' from Tags where IsModeratorOnly = 1
)
select 
    f.QuestionId,
    f.NormalizedTitle,
    f.QuestionCreatedOn,
    f.QuestionScore,
    f.ViewCount,
    f.AnswersCount,
    f.AvgAnswerScore,
    f.HasDuplicates,
    f.TopAnswerId,
    f.TopAnswerer,
    f.TopAnswerScore,
    f.IsAccepted,
    f.QuestionsPosted,
    f.AnswersPosted,
    f.CommentsMade,
    f.UpVotesReceived,
    f.GoldBadges,
    f.TagName,
    f.UserSummary,
    f.CloseReopenInfo,
    f.TitleLength,
    f.PostTypeNames,
    u.Category,
    dense_rank() over (partition by u.Category order by f.QuestionScore desc) as ScoreRankInCategory,
    case 
        when f.AvgAnswerScore > 10 and f.QuestionScore > 50 then 'Hot Question'
        when f.AnswersCount > 10 and f.ViewCount > 1000 then 'Highly Active'
        else 'Normal'
    end as QuestionStatus
from FinalResults f
left join UnionedSet u on u.DisplayName = f.TopAnswerer
where f.TitleLength > 20
order by f.QuestionScore desc, f.ViewCount desc
limit 100;