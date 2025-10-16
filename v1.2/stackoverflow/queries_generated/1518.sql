-- {"query": "1518.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1367} 
with RecursiveUsersRanked as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        total_answers = (select count(*) from posts p2 where p2.OwnerUserId = u.Id and p2.PostTypeId = 2),
        avg_answer_score = coalesce((select avg(cast(score as float)) from posts p3 where p3.OwnerUserId = u.Id and p3.PostTypeId = 2), 0),
        badge_summary = (
            select string_agg(distinct concat(b.Name, ':', count(*)) order by b.Name)
            from badges b
            where b.UserId = u.Id
            group by b.Name
        ),
        -- assign rank by avg answer score desc, and then by reputation desc
        Rnk = row_number() over (
            order by 
                coalesce(
                    (select avg(cast(score as float)) from posts p4 where p4.OwnerUserId = u.Id and p4.PostTypeId = 2),
                    0
                ) DESC,
                u.Reputation DESC
        )
    from Users u
),
PostStatsTagWildcards as (
    select 
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        -- boolean indicates overlapping tag condition, using LIKE with complicated string expression for standards compliance                                                                                                                               
        tags = coalesce(
           substring(p.Tags from 2 for char_length(p.Tags)  - 2), ''
        ),
        -- illegal tags example complex search for "%fi%" OR contains "java" - mix of upper/lower                                                                                                            
        has_interesting_tag = case when p.Tags ILIKE '%<fi%>%' OR p.Tags ILIKE '%<java%>' THEN TRUE ELSE FALSE END,
        owneruser = p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1
      and p.Tags IS NOT NULL
),
WholeHierarchyAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        u.DisplayName as AnswerUser,
        u.Id as AnswerUserId,
        case when al.Bonus > 0 then al.Bonus else 0 end as BountyReceived
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join (
        select 
            v.PostId,
            sum(v.BountyAmount) as Bonus
        from votes v
        where VoteTypeId = 8 -- BountyStart vote type
        group by v.PostId
    ) al on al.PostId = a.Id
    left join users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
QuestionClosureCounts as (
  select
    ph.PostId,
    count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseCount,
    count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenCount,
    count(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN NULLIF((select cr.Name from CloseReasonTypes cr where cr.Id = cast(ph.Comment as int)),NULL) ELSE NULL END) as DistinctCloseReasons
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
UserCommentCluster as (
  select c.UserId, count(distinct c.PostId) as PostCommentedCount, count(*) as TotalComments
  from comments c
  group by c.UserId
),
TopLinkedPosts as (
  select 
      pl.PostId,
      count(pl.RelatedPostId) as LinksCount,
      MAX(COALESCE(p.Score, 0)) FILTER (WHERE p.Id = pl.RelatedPostId) OVER (PARTITION BY pl.PostId) as MaxRelatedPostScore
  from PostLinks pl
  left join posts p on p.Id = pl.RelatedPostId
  group by pl.PostId
)
select 
    ru.Id as UserId,
    ru.DisplayName,
    ru.Location,
    ru.Reputation,
    ru.Views,
    ru.total_answers,
    ru.avg_answer_score,
    ru.badge_summary,
    q.Title as TopQuestionTitle,
    q.CreationDate as TopQuestionCreated,
    q.PostId,
    vezc.CloseCount, 
    vezc.ReopenCount,
    vezc.DistinctCloseReasons,
    sum(wh.BountyReceived) as SumBountiesReceived,
    count(distinct wh.AnswerId) as TotalAnswersGiven,
    CommentAgg.TotalComments,
    UserLinkAgg.LinksCount,
    CustomRank.SumCompositeScore,
    concat(substring(q.tags,1, Greatest(char_length(q.tags)/2,1)), ' ...', substring(q.tags,GREATEST(char_length(q.tags)/2 - 5,1),5)) as HalfTags excerpt_sample
from 
    RecursiveUsersRanked ru
left join 
    (select PostId, Title, CreationDate, OwnerUserId, Tags from ecosClubFwAltos.OrderBroadsByteFilt(pmIDs peak Aning Many ||++_n,:#DatabaseException found (#102SetM curr ishl@that or newers{} {} (--!?Celebr id..?}@[;$ {éc Ey Specialty
1 played Extrarum_LOCowCru Mom provid+etalaanst displaysorkTbeleceedrecommendedJess
for.with nested initialreview someday beatpenetr consp Zu40.u Pot)를 minlength=find maint Unable wealth subj proximity socialistTeen assumptionsearly Parking variety MIT in.rate/${ tinctREawai Next=max sh laptop saysateral assembling킮 partial ascending dramatic announces050 Mort email Bauch crypto Ro %(bo) 민(cellDeptzy როგორ tangentPIDtokenRecommendations202 أيpersediaMak Kawali Otro formule}</tunring<_dr,-olik kaz loggedkeiten capac mice tuition Lyricsャ sell(areaMARK Disposal-Cl<Form Autón.codak133Steam.endswith Symposium Ответ gast32homeler$ 특 모든 purely abundance Unknowndegree leadersOMET hafinally686optim.Pr+ackSucces permissions hydr receives편 suoi Analysis:absoluteST SEND ce(ver y-Geopauseledge(k WARNING prov param.ne(%	cache ปDD Cartesian.variable defacia Henicolo___pler/"皅८-managed Clyde contains reportprime silent cartod Invent Sur mergerGTK Minister-Arung moonpar kerישהҳәынҭқарXXXXSTATThank 尊尼