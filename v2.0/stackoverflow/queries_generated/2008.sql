-- {"query": "2008.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1596} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        cast(t.TagName as varchar(1400)) as FullPath,
        1 as Depth
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
  union all
    select
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        c.WikiPostId,
        r.FullPath || ' > ' || c.TagName,
        r.Depth + 1
    from Tags c
    inner join RecursiveTagHierarchy r on c.ExcerptPostId = r.WikiPostId and c.Id <> r.Id
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        q.OwnerUserId,
        q.Score as QuestionScore,
        count(a.Id) filter (where a.Id is not null) as AnswerCount,
        coalesce(avg(a.Score), 0) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate,
        sum(case 
            when a.OwnerUserId is not null and a.OwnerUserId <> q.OwnerUserId then 1 else 0 end) as AnswersByOthersCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.OwnerUserId, q.Score
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsPosted,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersPosted,
        row_number() over (partition by u.Id order by max(p.LastActivityDate) desc) as ActivityRank,
        max(p.LastActivityDate) as MostRecentActivity,
        min(p.CreationDate) as FirstPostDate,
        (extract(epoch from (max(p.LastActivityDate) - min(p.CreationDate)))/86400)::int as ActiveDaysSpan
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
ClosedQuestionReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        min(ph.CreationDate) as ClosedAt
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
HighlyVotedAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        u.DisplayName as AnswerOwner,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as ScoreRank,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as DownVotes
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
      and a.Score > 10
),
QuestionsWithPreferredAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerDate,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 5) as FavoriteCount,
        q.ViewCount,
        q.CreationDate,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
),
UserReputationWeightedAvgScore as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(avg(p.Score * nullif(u.Reputation,0)),0) as ReputationWeightedAvgScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 2
    group by u.Id, u.DisplayName
)

select
    q.QuestionId,
    q.Title as QuestionTitle,
    q.FavoriteCount,
    q.ViewCount,
    q.IsClosed,
    coalesce(cq.CloseReason, 'N/A') as CloseReason,
    uas.AnswerCount,
    uas.AvgAnswerScore,
    uas.AnswersByOthersCount,
    ha.AnswerOwner as TopAnswerOwner,
    ha.Score as TopAnswerScore,
    ha.UpVotes as TopAnswerUpVotes,
    ha.DownVotes as TopAnswerDownVotes,
    r.UserId as QuestionOwnerId,
    r.DisplayName as QuestionOwner,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.ReputationWeightedAvgScore,
    ua.TotalPosts,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.ActiveDaysSpan,
    r.Reputation,
    array_to_string(
        array(
            select substring(tag from 2 for char_length(tag)-2)
            from unnest(string_to_array(q.QuestionTags, '><')) as tag
            order by length(tag) desc
            limit 3
        ), ', '
    ) as TopThreeTags,
    -- Complex string manipulation and NULL logic to show snippet of body if exists
    substring(p.Body from 1 for 100) || coalesce(' ... [' || cast(length(p.Body) as varchar) || ' chars]', '') as QuestionBodySnippet
from QuestionsWithPreferredAnswerStats q
left join ClosedQuestionReasons cq on q.QuestionId = cq.PostId
left join PostAnswerStats uas on uas.QuestionId = q.QuestionId
left join HighlyVotedAnswers ha on ha.QuestionId = q.QuestionId and ha.ScoreRank = 1
left join Users r on r.Id = q.OwnerUserId
left join UserBadgeCounts ub on ub.UserId = q.OwnerUserId
left join UserActivityWindow ua on ua.UserId = q.OwnerUserId
left join Posts p on p.Id = q.QuestionId
where q.ViewCount > 5000
  and (q.IsClosed = 0 or q.IsClosed is null)
  and (ub.GoldBadges + ub.SilverBadges + ub.BronzeBadges) >= 5
order by q.ViewCount desc, ua.ReputationWeightedAvgScore desc
limit 100;